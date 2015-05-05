use 5.10.0;
use strict;
use warnings;

package Seq::KCManager;
# ABSTRACT: Manages KyotoCabinet db
# VERSION

use Moose 2;
use Moose::Util::TypeConstraints;

use Carp;
# use Cpanel::JSON::XS;
use KyotoCabinet;
use Storable qw/ freeze thaw /;
use Type::Params qw/ compile /;
use Types::Standard qw/ :types /;
use Hash::Merge qw/ merge _hashify _merge_hashes /;
use Cpanel::JSON::XS;

enum db_type => [qw/ hash btree /];

# use DDP;

with 'Seq::Role::IO';

my $i = 1;

has filename => (
  is       => 'ro',
  isa      => 'Str',
  required => 1,
);

has _db => (
  is      => 'ro',
  isa     => 'KyotoCabinet::DB',
  lazy    => 1,
  builder => '_build_db',
);

has db_type => (
  is       => 'ro',
  isa      => 'db_type',
  default  => 'hash',
  required => 1,
);

has _hash_merge => (
  is      => 'ro',
  isa     => 'Hash::Merge',
  builder => '_build_hash_merge',
  handles => ['merge'],
);

has no_bdb_insert => (
  is      => 'ro',
  isa     => 'Bool',
  default => 0,
);

sub _build_hash_merge {
  my $self       = shift;
  my $merge_name = 'merge_behavior_' . $i;
  $i++;
  my $merge = Hash::Merge->new();
  Hash::Merge::specify_behavior(
    {
      'SCALAR' => {
        'SCALAR' => sub {
          if   ( $_[0] eq $_[1] ) { $_[0] }
          else                    { join( ";", $_[0], $_[1] ) }
        },
        'ARRAY' => sub { [ $_[0],                          @{ $_[1] } ] },
        'HASH'  => sub { _merge_hashes( _hashify( $_[0] ), $_[1] ) },
      },
      'ARRAY' => {
        'SCALAR' => sub { [ @{ $_[0] },                     $_[1] ] },
        'ARRAY'  => sub { [ @{ $_[0] },                     @{ $_[1] } ] },
        'HASH'   => sub { _merge_hashes( _hashify( $_[0] ), $_[1] ) },
      },
      'HASH' => {
        'SCALAR' => sub { _merge_hashes( $_[0], _hashify( $_[1] ) ) },
        'ARRAY'  => sub { _merge_hashes( $_[0], _hashify( $_[1] ) ) },
        'HASH'   => sub { _merge_hashes( $_[0], $_[1] ) },
      },
    },
    $merge_name,
  );

  return $merge;
}

sub _build_db {
  my $self = shift;
  my $db = new KyotoCabinet::DB;
  if (!$db->open($self->filename, $db->OWRITER | $db->OCREATE)) {
      printf STDERR ("open error: %s\n", $db->error);
  }
  return $db;
}

# rationale - hash's cannot really have duplicate keys; so, to circumvent this
# issue we'll check to see if there's data there at they key first, unpack it
# and add our new data to it and then store the merged data
sub db_put {
  my ( $self, $key, $href ) = @_;

  #state $check = compile( Object, Str, HashRef );
  #my ( $self, $key, $href ) = $check->(@_);

  return if $self->no_bdb_insert;

  # check key
  my $old_href = $self->db_get($key);

  # is there data for the key?
  if ( defined $old_href ) {

    # merge hashes
    # p $old_href;

    for my $key ( keys %$old_href ) {
      my $new_val = $href->{$key};

      # is there a new value? if so, should we merge (i.e., is it not identical
      # to what's already stored? )
      if ($new_val) {
        my $old_val = $old_href->{$key};

        # if there's a difference then merge
        if ( $new_val ne $old_val ) {
          my @old_vals = split( /\;/, $old_val );
          $href->{$key} = join( ";", $new_val, @old_vals );
        }
      }
      else {
        # deal with the case where the key wasn't in the originally saved data
        $href->{$key} = $old_href->{$key};
      }
    }

    # my $new_href = $self->merge( $old_href, $href );
    # p $new_href;

    # save merged hash - using hash merge
    #$self->_db->set( $key, encode_json($new_href) );

    $self->_db->set( $key, freeze($href) );
  }
  else {
    $self->_db->set( $key, freeze($href) );
  }
}

sub db_get {
  my ($self, $key ) = @_;

  # state $check = compile( Object, Str );
  #my ( $self, $key ) = $check->(@_);

  my $val = $self->_db->get( $key );
  if (defined $val) {
    return thaw( $val );
  }
  else {
    return;
  }
}

__PACKAGE__->meta->make_immutable;

1;
