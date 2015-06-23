use 5.10.0;
use strict;
use warnings;

package Seq::KCManager;
# ABSTRACT: Manages KyotoCabinet db
# VERSION

use Moose 2;
use Moose::Util::TypeConstraints;

use Carp;
use Cpanel::JSON::XS;
use KyotoCabinet;
use Type::Params qw/ compile /;
use Types::Standard qw/ :types /;

enum db_type => [qw/ hash btree /];

with 'Seq::Role::IO';

has filename => (
  is       => 'ro',
  isa      => 'Str',
  required => 1,
);

# mode: - read or create
has mode => (
  is       => 'ro',
  isa      => 'Str',
  required => 1,
);

# bucket number for the file hash; KyotoCabinet docs indicate 50% to 400% of
# the number of stored elements should be used for optimal speed; this only
# needs to be set at creation
has bnum => (
  is      => 'ro',
  isa     => 'Int',
  default => 10_000_000,
);

# size of mapped memory - set for read/write
has msiz => (
  is      => 'ro',
  isa     => 'Int',
  default => 1_280_000_000,
);

has _db => (
  is      => 'ro',
  isa     => 'KyotoCabinet::DB',
  lazy    => 1,
  builder => '_build_db',
);

sub _build_db {
  my $self = shift;

  my $this_msiz = join "=", "msiz", $self->msiz;

  if ( $self->mode eq 'create' ) {
    my $this_bnum = join "=", "bnum", $self->bnum;

    # this option is recommended when creating a db with a prespecified bucket
    # number
    my $options          = "opts=HashDB::TLINEAR";
    my $params           = join "#", $options, $this_bnum;
    my $file_with_params = join "#", $self->filename, $params;
    my $db               = new KyotoCabinet::DB;

    if ( !$db->open( $file_with_params, $db->OWRITER | $db->OCREATE ) ) {
      printf STDERR "open error: %s\n", $db->error;
    }
    return $db;
  }
  elsif ( $self->mode eq 'read' ) {
    my $file_with_params = join "#", $self->filename, $this_msiz;
    my $db = new KyotoCabinet::DB;

    if ( !$db->open( $file_with_params, $db->OREADER ) ) {
      printf STDERR "open error: %s\n", $db->error;
    }
    return $db;
  }
  else {
    croak "ERROR: expected mode to be 'read' or 'create' but got: " . $self->mode;
  }
}

# rationale - hashes cannot really have duplicate keys; so, to circumvent this
# issue we'll check to see if there's data there at they key first, unpack it
# and add our new data to it and then store the merged data
sub db_put {
  my ( $self, $key, $href ) = @_;

  my $existing_aref = $self->db_get($key);

  if ( defined $existing_aref ) {
    my @data = @$existing_aref;
    push @data, $href;
    $self->_db->set( $key, encode_json( \@data ) );
  }
  else {
    $self->_db->set( $key, encode_json( [$href] ) );
  }
  #
  # # is there data for the key?
  # if ( $self->_db->check($key) > 0 ) {
  #
  #   # get database data value
  #   my $old_href = $self->db_get($key);
  #
  #   # get all keys from old and new data
  #   my @keys = ( keys %$old_href, keys %$href );
  #
  #   for my $keys (@keys) {
  #
  #     # retrieve values for old and new hash data
  #     my $new_val = $href->{$key};
  #     my $old_val = $old_href->{$key};
  #
  #     # merge hash - we have a predictable strucutre, which simplifies what
  #     # we need to deal with - there will only be string values or hashref
  #     # values;
  #
  #     if ( defined $new_val ) {
  #       if ( defined $old_val ) {
  #         if ( ref $old_val eq "HASH" && ref $new_val eq "HASH" ) {
  #           my @sub_keys = ( keys %$old_val, keys %$new_val );
  #           for my $sub_key (@sub_keys) {
  #             my $new_sub_val = $new_val->{$sub_key};
  #             my $old_sub_val = $old_val->{$sub_key};
  #             if ( defined $new_sub_val ) {
  #               if ( defined $old_sub_val ) {
  #                 if ( $new_sub_val ne $old_sub_val ) {
  #                   my @old_sub_vals = split /\;/, $old_sub_val;
  #                   $href->{$key}{$sub_key} = join ";", $new_sub_val, @old_sub_vals;
  #                 }
  #               }
  #             }
  #             else {
  #               if ( defined $old_sub_val ) {
  #                 $href->{$key}{$sub_key} = $old_val;
  #               }
  #             }
  #           }
  #         }
  #         elsif ( $old_val ne $new_val ) {
  #           my @old_vals = split( /\;/, $old_val );
  #           $href->{$key} = join( ";", $new_val, @old_vals );
  #         }
  #       }
  #     }
  #     else {
  #       if ( defined $old_val ) {
  #         $href->{$key} = $old_val;
  #       }
  #     }
  #   }
  #   $self->_db->set( $key, encode_json($href) );
  # }
  # else {
  #   $self->_db->set( $key, encode_json($href) );
  # }
}

sub db_get {
  my ( $self, $key ) = @_;

  my $val = $self->_db->get($key);
  if ( defined $val ) {
    return decode_json $val;
  }
  else {
    return;
  }
  #
  # if ( $self->_db->check($key) > 0 ) {
  #   return decode_json( $self->_db->get($key) );
  # }
  # else {
  #   return;
  # }
}

__PACKAGE__->meta->make_immutable;

1;
