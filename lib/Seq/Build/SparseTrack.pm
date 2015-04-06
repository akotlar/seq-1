use 5.10.0;
use strict;
use warnings;

package Seq::Build::SparseTrack;
# ABSTRACT: Base class for sparse track building
# VERSION

use Moose 2;

use MongoDB;
use namespace::autoclean;

use Seq::Build::GenomeSizedTrackStr;

extends 'Seq::Config::SparseTrack';

has genome_index_dir => (
  is       => 'ro',
  isa      => 'Str',
  required => 1,
);

has genome_name => (
  is       => 'ro',
  isa      => 'Str',
  required => 1,
);

has genome_track_str => (
  is       => 'ro',
  isa      => 'Seq::Build::GenomeSizedTrackStr',
  required => 1,
  handles  => [ 'get_abs_pos', 'get_base', 'exists_chr_len' ],
);

has mongo_connection => (
  is       => 'ro',
  isa      => 'Seq::MongoManager',
  required => 1,
);

has bdb_connection => (
  is => 'ro',
  isa => 'Seq::BDBManager',
  required => 1,
  handles => [ 'db_put', 'db_get' ],
);

has counter => (
  traits  => ['Counter'],
  is      => 'ro',
  isa     => 'Num',
  default => 0,
  handles => {
    inc_counter   => 'inc',
    dec_counter   => 'dec',
    reset_counter => 'reset',
  }
);

has bulk_insert_threshold => (
  is      => 'ro',
  isa     => 'Num',
  default => 10_000,
);

has _mongo_bulk_handler => (
  is      => 'rw',
  isa     => 'MongoDB::BulkWrite',
  clearer => '_clear_mongo_bulk_handler',
  builder => '_build_mongo_bulk_handler',
  handles => [ 'insert', 'execute' ],
  lazy    => 1,
);

sub _build_mongo_bulk_handler {
  my $self = shift;
  return $self->mongo_connection->_mongo_collection( $self->name )
    ->initialize_ordered_bulk_op;
}

after insert => sub {
  my $self = shift;
  $self->inc_counter;
};

after execute => sub {
  my $self = shift;
  $self->reset_counter;
  $self->_clear_mongo_bulk_handler;
  $self->_build_mongo_bulk_handler;
};

__PACKAGE__->meta->make_immutable;

1;
