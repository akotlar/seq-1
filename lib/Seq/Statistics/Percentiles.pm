package Seq::Statistics::Percentiles;

use strict;
use warnings;
use Moose;
with 'Seq::Statistics::Percentiles::QualityControl';

use namespace::autoclean;
use Carp qw/cluck confess/;

#all percentiles investigated
has percentileThresholdNames =>
( is      => 'ro',
  traits => ['Array'],
  isa     => 'ArrayRef[Num]',
  default => sub{ return ['5th', 'median', '95th'] },
  handles => {
    getThresholdName => 'get',
  }
);

has percentileThresholds =>
( is      => 'ro',
  traits => ['Array'],
  isa     => 'ArrayRef[Num]',
  default => sub{ return [.05, .50, .95] },
  handles => {
    getThreshold => 'get',
  }
);

has ratioName => 
(
  is => 'ro',
  isa => 'Str',
  required => 1,
);

#should always contain keys 5 and 95; maybe later we allow any keys set by
has ratios =>
(
  is  => 'rw',
  isa => 'ArrayRef[Num]',
  traits => ['Array'],
  handles => {
    sortRatios => 'sort_in_place',
    getRatio => 'get',
    numRatios => 'count',
  },
  required => 1,
);

has percentiles => 
(
  is => 'HashRef',
  isa => 'HashRef[Num]',
  traits => ['Hash'],
  handles => {
    setPercentile => 'set',
    getPercentile => 'get',
    getPercentilesKv => 'kv',
    hasNoPercentiles => 'is_empty',
  },
  required => 1,
  init_arg => undef,
);

sub BUILD
{
  my $self = shift;

  $self->sortRatios;
}

sub makePercentiles
{
  my $self = shift;
  my $lastIndex = $self->numRatios - 1;

  my ($maybeIndex, $floor, $ceil, $lowerVal, $higherVal);
  
  my $thIndex = 0;
  for my $threshold (@$self->percentileThresholds)
  {
    $self->setPercentile($self->getThresholdName($thIndex, sub
    {
      $maybeIndex = $lastIndex * $threshold;
      $floor = floor($maybeIndex);
      $ceil = ceil($maybeIndex);
      if($ceil == $floor)
      { 
        return $self->getRatio($ceil); 
      }
      else
      {
        #distance interpolated composite value
        my $lowerVal = $self->getRatio($floor) * ($maybeIndex - $floor);
        my $higherVal = $self->getRatio($ceil) * ($ceil - $maybeIndex);

        return $lowerVal + $higherVal;
      }
    } ) );
    $thIndex++;
  } 
}

sub storePercentiles
{
  my ($self, $targetHref) = @_;

  for my $kv ($self->getPercentilesKv)
  {
    $targetHref->{$kv->[0] } = $kv->[1];
  }
}
__PACKAGE__->meta->make_immutable;
1;
