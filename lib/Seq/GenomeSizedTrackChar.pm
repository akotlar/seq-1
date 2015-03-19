package Seq::GenomeSizedTrackChar;

use 5.10.0;
use Carp qw( confess croak );
use File::Path;
use File::Spec;
use Moose;
use namespace::autoclean;
use Scalar::Util qw( reftype );
use YAML::XS;
extends 'Seq::Config::GenomeSizedTrack';
with 'Seq::Role::IO', 'Seq::Role::Genome';

=head1 NAME

Seq::GenomeSizedTrackChar - The great new Seq::Seq::GenomeSizedTrackChar!

=head1 VERSION

Version 0.01

=cut

our $VERSION = '0.01';

has genome_length => (
  is => 'rw',
  isa => 'Int',
);

has chr_len => (
  is => 'rw',
  isa => 'HashRef[Str]',
  traits => ['Hash'],
  handles => {
    exists_chr_len => 'exists',
    get_chr_len => 'get',
  },
);

# stores the 1-indexed length of each chromosome
has char_seq => (
  is => 'rw',
  lazy => 1,
  builder => '_build_char_seq',
  isa => 'ScalarRef',
  clearer => 'clear_char_seq',
  predicate => 'has_char_seq',
);

# holds a subroutine that converts chars to a score for the track, which is
#   used to decode the score
has char2score => (
  is => 'ro',
  isa => 'CodeRef',
);

# holds a subroutine that converts scores to a char for the track, which is
#   used to encode the scores

has score2char => (
  is => 'ro',
  isa => 'CodeRef',
);

=head2 _build_char_seq

=cut

sub _build_char_seq {
    my ($self, $genome_seq) = @_;
    return \$genome_seq;
}

=head2 get_base

=cut
sub get_base {
  my ($self, $pos) = @_;
  my $seq_len = $self->genome_length;

  confess "get_base() expects a position between 0 and  $seq_len, got $pos."
    unless $pos >= 0 and $pos < $seq_len;

  # position here is not adjusted for the Zero versus 1 index issue
  return unpack ('C', substr( ${$self->char_seq}, $pos, 1));
}

=head2 get_score

=cut

sub get_score {
  my ($self, $pos) = @_;

  confess "get_score() requires absolute genomic position (0-index)"
    unless defined $pos;
  confess "get_score() expects score2char() to be a coderef"
    unless $self->meta->has_method( 'char2score' )
      and reftype($self->char2score) eq 'CODE';
  confess "get_score() called on non-score track"
    unless $self->type eq 'score';

  my $char = $self->get_base( $pos );
  return $self->char2score->( $char );
}

sub BUILDARGS {
  my $class = shift;
  my $href  = $_[0];
  if (scalar @_ > 1 || reftype($href) ne "HASH")
  {
    confess "Error: $class expects hash reference.\n";
  }
  else
  {
    my %hash;
    if ($href->{type} eq "score")
    {
      if ($href->{name} eq "phastCons")
      {
        $hash{score2char}  = sub {
          my $score = shift;
          return (int ( $score * 254 ) + 1)
          };
        $hash{char2score} = sub {
          my $score = shift;
          return ( $score- 1 ) / 254
          };
      }
      elsif ($href->{name} eq "phyloP")
      {
        $hash{score2char}  = sub {
          my $score = shift;
          return (int ( $score * ( 127 / 30 ) ) + 128)
          };
        $hash{char2score} = sub {
          my $score = shift;
          return ( $score - 128 ) / ( 127 / 30 )
          };
      }
    }

    # add remaining values to hash
    # if char2score or score2char are set
    # then the defaults will be overridden
    for my $attr (keys %$href)
    {
      $hash{$attr} = $href->{$attr};
    }
    return $class->SUPER::BUILDARGS(\%hash);
  }
}

__PACKAGE__->meta->make_immutable;

1;
