use 5.10.0;
use strict;
use warnings;

package Seq::GenomeSizedTrackChar;
# ABSTRACT: Decodes genome sized char tracks - genomes, scores, etc.
# VERSION

use Moose 2;

use Carp qw/ confess croak /;
use File::Path;
use File::Spec;
use namespace::autoclean;
use Scalar::Util qw/ reftype /;
use YAML::XS;

extends 'Seq::Config::GenomeSizedTrack';
with 'Seq::Role::IO', 'Seq::Role::Genome';

has genome_length => (
  is  => 'rw',
  isa => 'Int',
);

has chr_len => (
  is      => 'rw',
  isa     => 'HashRef[Str]',
  traits  => ['Hash'],
  handles => {
    exists_chr_len     => 'exists',
    char_genome_length => 'get',
  },
);

# stores the 0-indexed length of each chromosome
has char_seq => (
  is  => 'ro',
  isa => 'ScalarRef',
);

# holds a subroutine that converts chars to a score for the track, which is
#   used to decode the score
sub char2score {
  my ( $self, $char ) = shift;
  return ( ( ( $char - 1 ) / $self->score_beta ) + $self->score_min );
}

sub get_base {
  my ( $self, $pos ) = @_;
  state $genome_length = $self->genome_length;

  confess "get_base() expects a position between 0 and $genome_length, got $pos."
    unless $pos >= 0 and $pos < $genome_length;

  # position here is not adjusted for the Zero versus 1 index issue
  return unpack( 'C', substr( ${ $self->char_seq }, $pos, 1 ) );
}

sub get_score {
  my ( $self, $pos ) = @_;

  confess "get_score() requires absolute genomic position (0-index)"
    unless defined $pos;
  confess "get_score() expects score2char() to be a coderef"
    unless $self->meta->has_method('char2score')
    and reftype( $self->char2score ) eq 'CODE';
  confess "get_score() called on non-score track"
    unless $self->type eq 'score';

  my $char = $self->get_base($pos);
  return sprintf( "%.03f", $self->char2score->($char) );
}

sub BUILDARGS {
  my $class = shift;
  my $href  = $_[0];
  if ( scalar @_ > 1 || reftype($href) ne "HASH" ) {
    confess "Error: $class expects hash reference.\n";
  }
  else {
    my %hash;
    if ( $href->{type} eq "score" ) {
      if ( $href->{name} eq "phastCons" ) {
        $hash{score_R}   = 254;
        $hash{score_min} = 0;
        $hash{score_max} = 1;
      }
      elsif ( $href->{name} eq "phyloP" ) {
        $hash{score_R}   = 127;
        $hash{score_min} = -30;
        $hash{score_max} = 30;
      }
    }

    # if score_R, score_min, or score_max are set by the caller then the
    # following will override it
    for my $attr ( keys %$href ) {
      $hash{$attr} = $href->{$attr};
    }
    return $class->SUPER::BUILDARGS( \%hash );
  }
}

__PACKAGE__->meta->make_immutable;

1;
