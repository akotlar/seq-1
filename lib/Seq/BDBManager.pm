use 5.10.0;
use strict;
use warnings;

package Seq::BDBManager;
# ABSTRACT: Manages mongo db connections
# VERSION

use Moose 2;
use Moose::Util::TypeConstraints;

use Carp;
use Cpanel::JSON::XS;
use DB_File;
use Storable qw/ freeze thaw /;
use Type::Params qw/ compile /;
use Types::Standard qw/ :types /;
use Hash::Merge;

use DDP;

with 'Seq::Role::IO';

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

has _hash_merge => (
  is => 'ro',
  isa => 'Hash::Merge',
  builder => '_build_hash_merge',
);

sub _build_hash_merge {
  my $self = shift;
  return Hash::Merge->new('RETAINMENT_PRECEDENT');
}

sub _build_db {
  my $self = shift;
  my %hash;
  my $db = tie %hash, 'DB_File', $self->filename, O_RDWR|O_CREAT, 0666, $DB_HASH
    or confess 'Cannot open file: ' . $self->filename . ": $!\n";
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
    my $new_href = $self->_hash_merge( $old_href, $href );
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
