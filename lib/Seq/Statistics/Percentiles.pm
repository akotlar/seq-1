package Seq::Statistics::Percentiles;

use strict;
use warnings;
use Moose::Role;

use Carp qw/cluck confess/;

#all percentiles investigated
has percentilesRef =>
( is      => 'ro',
  isa     => 'ArrayRef[Num]',
  default => sub{ [.05, .50, .95] },
  predicate => 'has_confidenceIntervalRef'
);

has percentilesKey =>
(
  is      => 'ro',
  isa     => 'Str',
  default => 'percentiles',
  init_arg => undef 
);

#should always contain keys 5 and 95; maybe later we allow any keys set by 
has ratioPercentilesRef =>
(
  is  => 'rw',
  isa => 'HashRef[HashRef[Num]]',
  lazy => '1',
  default => sub{ {} },
  init_arg => undef
);

sub calculate
{
  my $self = shift;
  my $ratioCollectionReference = shift;
  
  #sort decimal percentiles ascending; are we ok with this side-effect , or better to copy the array?
  @{$self->percentilesRef} = sort{$a <=> $b} @{$self->percentilesRef}; 

  for my $ratioKey (keys %$ratioCollectionReference )
  { 
    #sort array ascending; are we ok with this side-effect , or better to copy the array?
    @{ $ratioCollectionReference->{$ratioKey} } = sort{ $a <=> $b } @{ $ratioCollectionReference->{$ratioKey} }; 

    my @percentileValues;
    for my $percentile ( @{$self->percentilesRef} )
    {
      push @percentileValues, $self->_getPercentile($ratioCollectionReference->{$ratioKey},$percentile);
    }
    $self->ratioPercentilesRef->{$ratioKey}->{ $self->percentilesKey } = \@percentileValues;

    print "\nThe " . join(",",@{$self->percentilesRef}) ." percentiles of $ratioKey are ". join(",",@percentileValues) . "\n\n" if $self->verbose;
  }
}

#todo: check that percentiles between 0 and 1
sub _getPercentile 
{
  my $self = shift;
  my ($arrayReference,$percentileFactor) = @_;
  
  my $lastIndex = scalar $#{$arrayReference};
  my $maybeIndex = $lastIndex * $percentileFactor;
  my $floor = floor($maybeIndex);
  my $ceil = ceil($maybeIndex);

  if($ceil == $floor)
  { 
    return $arrayReference->[$ceil]; 
  }
  else
  {
    my $lowerVal = $arrayReference->[$floor] * ($maybeIndex - $floor);
    my $higherVal = $arrayReference->[$ceil] * ($ceil - $maybeIndex);

    return $lowerVal + $higherVal;
  }
}

no Moose::Role;
1;