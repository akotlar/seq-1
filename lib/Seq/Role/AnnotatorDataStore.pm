use strict;
use warnings;
use feature "state";

package Seq::Role::AnnotatorDataStore;

# ABSTRACT: Builds a plain text genome used for binary genome creation
# VERSION
use Moose::Role;
use Carp qw/ croak /;
use File::Spec;
use namespace::autoclean;
use Type::Params qw/ compile /;
use Types::Standard qw/ :types /;

use DDP;

use threads;
use threads::shared;

my $_genomeDataHref : shared =
  shared_clone( {} ); #a class variable holding our thread-shared data

has _genomeDataHref => (
  traits   => ['Hash'],
  is       => 'rw',
  isa      => 'HashRef',
  handles  => { hasSeq => 'exists', getSeq => 'get', storeSeq => 'set' },
  init_arg => undef,
  default => sub { return $_genomeDataHref; }
);

my $shared_count : shared = 0; #debug, to be removed
my $count : shared        = 0; #debug, to be removed

sub load_genome_sequence {

  #self, $sequence_file_name, $sequence_file_parent_path
  state $check = compile( Object, Str, Str );
  my ( $self, $sequence_file_name, $sequence_file_parent_path ) = $check->(@_);

  $count += 1;

  print "\nTotal count run $count\n";

  #$sequence_file_name acts as sequence hash key
  if ( $self->hasSeq($sequence_file_name) ) {
    $shared_count += 1;
    print "\nShared the data $shared_count times.\n";

    #returns anonymous array [\$seq,$genome_length]
    return $self->getSeq($sequence_file_name);
  }

  $sequence_file_parent_path = File::Spec->rel2abs($sequence_file_parent_path);
  my $sequence_file_path =
    File::Spec->catfile( $sequence_file_parent_path, $sequence_file_name );
  my $genome_seq_fh = $self->get_read_fh($sequence_file_path);
  binmode $genome_seq_fh;

  my $genome_length = -s $sequence_file_path;

  my $seqRef : shared = shared_clone( [] );

  $seqRef->[0] = '';
  $seqRef->[1] = $genome_length;

  # error check the idx_file
  croak "ERROR: expected file: '$sequence_file_path' does not exist."
    unless -f $sequence_file_path;
  croak "ERROR: expected file: '$sequence_file_path' is empty." unless $genome_length;

  read $genome_seq_fh, $seqRef->[0], $genome_length;

  $self->storeSeq( $sequence_file_name, $seqRef );

  return $seqRef;
}

no Moose::Role;

1;
