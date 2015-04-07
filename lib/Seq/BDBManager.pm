use 5.10.0;
use strict;
use warnings;

package Seq::BDBManager;
# ABSTRACT: Manages BerkeleyDB connections
# VERSION

use Moose 2;
use Moose::Util::TypeConstraints;

use Carp;
use Cpanel::JSON::XS;
use DB_File;
use Storable qw/ freeze thaw /;
use Type::Params qw/ compile /;
use Types::Standard qw/ :types /;
use Hash::Merge qw/ merge _hashify _merge_hashes /;

# use DDP;

enum bdb_type => [qw/ hash btree /];

with 'Seq::Role::IO';

my $i = 1;

has filename => (
  is => 'ro',
  isa => 'Str',
  required => 1,
);

has _db => (
  is => 'ro',
  isa => 'DB_File',
  lazy => 1,
  builder => '_build_db',
);

has db_type => (
  is => 'ro',
  isa => 'bdb_type',
  default => 'hash',
  required => 1,
);

has _hash_merge => (
  is => 'ro',
  isa => 'Hash::Merge',
  builder => '_build_hash_merge',
  handles => [ 'merge' ],
);

sub _build_hash_merge {
  my $self = shift;
  my $merge_name = 'merge_behavior_' . $i;
  $i++;
  my $merge = Hash::Merge->new();
  Hash::Merge::specify_behavior( {
      'SCALAR' => {
          'SCALAR' => sub { if ( $_[0] eq $_[1] ) { $_[0] } else { join(";", $_[0], $_[1]) } },
          'ARRAY'  => sub { [ $_[0], @{ $_[1] } ] },
          'HASH'   => sub { _merge_hashes( _hashify( $_[0] ), $_[1] ) },
      },
      'ARRAY' => {
          'SCALAR' => sub { [ @{ $_[0] },                     $_[1] ] },
          'ARRAY'  => sub { [ @{ $_[0] }, @{ $_[1] } ] },
          'HASH'   => sub { _merge_hashes( _hashify( $_[0] ), $_[1] ) },
      },
      'HASH' => {
          'SCALAR' => sub { _merge_hashes( $_[0], _hashify( $_[1] ) ) },
          'ARRAY'  => sub { _merge_hashes( $_[0], _hashify( $_[1] ) ) },
          'HASH'   => sub { _merge_hashes( $_[0], $_[1] ) },
      },
    }, $merge_name,
  );

  return $merge;
}

sub _build_db {
  my $self = shift;
  my (%hash, $db);
  if ($self->_db_type eq 'hash') {
    $db = tie %hash, 'DB_File', $self->filename, O_RDWR|O_CREAT, 0666, $DB_HASH
      or confess 'Cannot open file: ' . $self->filename . ": $!\n";
  }
  else {
    $db = tie %hash, 'DB_File', $self->filename, O_RDWR|O_CREAT, 0666, $DB_BTREE
      or confess 'Cannot open file: ' . $self->filename . ": $!\n";
  }
  return $db;
}

# rationale - hash's cannot really have duplicate keys; so, to circumvent this
# issue we'll check to see if there's data there at they key first, unpack it
# and add our new data to it and then store the merged data
sub db_put {
  state $check = compile( Object, Str, HashRef );
  my ($self, $key, $href) = $check->(@_);

  # check key
  my $old_href = $self->db_get( $key );

  # is there data for the key?
  if (defined $old_href) {
    # merge hashes
    # p $old_href;

    my $new_href = $self->merge( $old_href, $href );

    # p $new_href;

    # save merged hash
    $self->_db->put( $key, freeze( $new_href ) );
  }
  else {
    $self->_db->put( $key, freeze( $href ) );
  }
}

sub db_get {
  state $check = compile( Object, Str );
  my ($self, $key) = $check->(@_);

  my $val;
  if ( $self->_db->get( $key, $val ) == 0 ) {
    return thaw( $val );
  }
  else {
    return;
  }
}

__PACKAGE__->meta->make_immutable;

1;
