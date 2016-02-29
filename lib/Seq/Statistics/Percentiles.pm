package Seq::Statistics::Percentiles;

our $VERSION = '0.001';

# ABSTRACT: A class for generating percentiles
# VERSION

use 5.10.0;
use strict;
use warnings;
use Moose;

use namespace::autoclean;
use Carp qw/cluck confess/;
use POSIX; #ceil, floor
use DDP;

has percentilesKey => (
  is      => 'ro',
  isa     => 'Str',
  default => 'percentiles',
);

#all percentiles investigated
has percentileThresholdNames => (
  is      => 'ro',
  traits  => ['Array'],
  isa     => 'ArrayRef[Str]',
  default => sub { return [ '5th', 'median', '95th' ] },
  handles => { getThresholdName => 'get', }
);

has percentileThresholds => (
  is      => 'ro',
  traits  => ['Array'],
  isa     => 'ArrayRef[Num]',
  default => sub { return [ .05, .50, .95 ] },
  handles => {
    getThreshold  => 'get',
    allThresholds => 'elements',
  }
);

#expects array of [ratioID, ratioValue]
#ex: [ ['sample1', 2.2] ]
has ratios => (
  is      => 'rw',
  isa     => 'ArrayRef[ArrayRef[Str|Num]]',
  traits  => ['Array'],
  handles => {
    removeRatio => 'splice',
    sortRatios  => 'sort_in_place',
    getRatioID  => 'get',
    getRatio    => 'get',
    numRatios   => 'count',
    allRatios   => 'elements',
  },
  required => 1,
);

has lastRatioIdx => (
  is      => 'ro',
  isa     => 'Num',
  lazy    => 1,
  builder => '_buildNumRatios',
);

sub _buildNumRatios {
  my $self = shift;
  return $self->numRatios - 1;
}

around 'sortRatios' => sub {
  my $orig = shift;
  my $self = shift;
  return $self->$orig( sub { $_[0][1] <=> $_[1][1] } );
};

around 'getRatioID' => sub {
  my $orig = shift;
  my $self = shift;
  return $self->$orig(@_)->[0];
};

around 'getRatio' => sub {
  my $orig = shift;
  my $self = shift;
  return $self->$orig(@_)->[1]; #the ratio is in pos 1
};

around 'removeRatio' => sub {
  my $orig = shift;
  my $self = shift;
  return $self->$orig( @_, 1 );
};

has percentiles => (
  is      => 'rw',
  isa     => 'ArrayRef[ArrayRef[Str|Num]]',
  traits  => ['Array'],
  handles => {
    setPercentile  => 'push',
    getPercName    => 'get',
    getPercVal     => 'get',
    numPercentiles => 'count',
    hasPercentiles => 'count',
  },
  required => 1,
  default  => sub { return [] },
  init_arg => undef,
);

#accepts, index of threshold, threshold value
around 'setPercentile' => sub {
  my $orig = shift;
  my $self = shift;
  return $self->$orig(
    [ $self->getThresholdName( $_[0] ), $self->_calcPercentile( $_[1] ) ] );
};

around 'getPercName' => sub {
  my $orig = shift;
  my $self = shift;
  return $self->$orig(@_)->[0];
};

around 'getPercVal' => sub {
  my $orig = shift;
  my $self = shift;
  return $self->$orig(@_)->[1];
};

has ratioName => (
  is       => 'ro',
  isa      => 'Str',
  required => 1,
);

#TODO: figure out way of iteratively building nested hash usind 'set'
has target => (
  is       => 'rw',
  isa      => 'HashRef',
  traits   => ['Hash'],
  handles  => { addToTarget => 'set', },
  required => 1,
);

has debug => (
  is      => 'ro',
  isa     => 'Int',
  default => 0,
);

with 'Seq::Statistics::Percentiles::QualityControl';

sub BUILD {
  my $self = shift;

  if ( $self->debug ) {
    say "In percentiles, evaluating " . $self->ratioName;
    say "before screen ratios, ratios are";
    p $self->ratios;
  }

  $self->screenRatios;

  if ( $self->debug ) {
    say "after screening, remaining ratios are:";
    p $self->ratios;
    say "blascklisted ids are";
    p $self->preScreened;
  }

  $self->sortRatios; #asc order

  if ( $self->debug ) {
    say "after sorting, ratios are:";
    p $self->ratios;
    say "after sorting we have this many ratios: " . $self->numRatios;
  }

  $self->makePercentiles;
}

sub makePercentiles {
  my $self = shift;

  my $thIdx = 0;
  for my $thold ( $self->allThresholds ) {
    $self->setPercentile( $thIdx, $thold );
    $thIdx++;
  }
}

sub storeAndQc {
  my $self = shift;

  my $pKey = $self->percentilesKey;
  my $rKey = $self->ratioName;
  for my $idx ( 0 ... $self->numPercentiles - 1 ) {
    $self->target->{$pKey}{$rKey}{ $self->getPercName($idx) } = $self->getPercVal($idx);
  }

  $self->qc;
}

# runs through array twice, once to find bad elements, once to remove those elements
# expects infinity to be represented as any value < 0
sub screenRatios {
  my $self = shift;
  my @newArray;
  for my $ratio ( $self->allRatios ) {
    # don't do this; inf is a valid ratio, and the 5th, 95th could be inf
    # if ( $ratio->[1] < 0 ) { #inf check;
    #   $self->blacklistID( $ratio->[0] );
    #   next;
    # }
    push @newArray, $ratio;
  }

  $self->ratios( \@newArray );
}

#todo: should we return -9 for missing data?
sub _calcPercentile {
  my ( $self, $threshold ) = @_;

  if ( $self->numRatios == 0 ) {
    return;
  }

  my $fractionalIdx = $self->lastRatioIdx * $threshold;

  my $floorIdx = floor($fractionalIdx);
  my $ceilIdx  = ceil($fractionalIdx);

  if ( $ceilIdx == $floorIdx ) {
    say "Ratio for $threshold: index $ceilIdx, val " . $self->getRatio($ceilIdx)
      if $self->debug;
    return $self->getRatio($ceilIdx);
  }
  else {
    # if we wish to use rank interpololation
    # my $fractionalRank = $self->numRatios * $threshold;
    # my $awayFromFloor = $fractionalRank - floor($fractionalRank);

    # my $higherVal  = $self->getRatio($ceilIdx) * $awayFromFloor;
    # my $lowerVal = $self->getRatio($floorIdx) *  (1 - $awayFromFloor);

    #index interpolation
    my $higherVal = $self->getRatio($ceilIdx) *  ( $fractionalIdx - $floorIdx );
    my $lowerVal  = $self->getRatio($floorIdx) * ( $ceilIdx - $fractionalIdx );

    say "Ratio for $threshold, btwn indices $ceilIdx & $floorIdx, interp to "
      . ( $lowerVal + $higherVal )
      if $self->debug;
    return $lowerVal + $higherVal;
  }
}
__PACKAGE__->meta->make_immutable;
1;
