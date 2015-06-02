use 5.10.0;
use strict;
use warnings;

package Seq::Cadd;

# ABSTRACT: Builds a plain text genome used for binary genome creation
# VERSION

use Moose 2;
use Carp qw/ croak /;
use Path::Tiny qw/ path /;
use namespace::autoclean;
use Scalar::Util qw/ reftype /;
use Type::Params qw/ compile /;
use Types::Standard qw/ :types /;
use YAML::XS qw/ LoadFile /;

use Seq::GenomeSizedTrackChar;

with 'Seq::Role::IO', 'Seq::Role::Genome' 'MooX::Role::Logger';


# TODO: need to load CADD scores into an array
#   - follow Seq::Annotate function => sub _load_genome_sized_track

sub get_cadd_score {
  my ($self, $abs_pos, $ref_base, $new_base ) = @_;
  my $score;
  
  # TODO:
  #   - decide which CADD string is the right one
  #   - use get_score from Seq::GenomeSizedTrackChar
  #   
  return $score;
}

