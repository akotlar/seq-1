package Seq::Statistics::Ratios;
our $VERSION = '0.001';

use 5.10.0;
use strict;
use warnings;
use Moose::Role;

use Carp qw(cluck confess);
use DDP;

requires 'statsKey';
requires 'countKey';
requires 'ratioKey';
requires 'statsRecord';

has ratioFeaturesRef =>
( is      => 'ro',
  traits  => ['Hash'],
  isa     => 'HashRef[ArrayRef[Str]]',
  handles => {
    ratioNumerators => 'keys',
    ratioFeaturesKv => 'kv',
    allowedNumerator => 'exists',
    getDenomRatioKeys => 'get',
  },
  builder => '_buildRatioFeaturesRef'
);

# each key should be the ratio name, each value all ratios for that name
# one ratio per sample
has ratiosHref =>
(
  is => 'rw',
  isa => 'HashRef[ArrayRef]',
  traits => ['Hash'],
  handles => {
    allRatiosKv => 'kv',
    allRatioVals => 'values',
    ratios => 'get',
    hasRatioCollection => 'defined',
    hasNoRatios => 'is_empty',
  }
);
# numeratorKey=>[denominatorKey,ratioKey] 
sub _buildRatioFeaturesRef
{
  my $self = shift;
  return {
    Silent => ['Replacement','Silent:Replacement'],
    Transitions => ['Transversions', 'Transitions:Transversions'],
  };   
}

sub makeRatios
{
  my $self= shift;

  my $statsKey = $self->statsKey;
  
  #calculate ratios for samples;
  my ($ratio, $allRatios, $ratioKey, $numerator, $denominator);
  for my $rKv ($self->ratioFeaturesKv) #return [denom.[denom, ratioKey]]
  {
    for my $sKv ($self->statsKv) #return [sampleID.{HashRef}]
    {
      ($numerator, $denominator) = 
        $self->_recursiveCalc($rKv->[0], $rKv->[1][0], $sKv->[1] );

      $ratio = $self->_calcRatio($numerator, $denominator);
      if(defined $ratio)
      {
        $ratioKey = $rKv->[1][1];
        $sKv->[1]{$self->statsKey}{$ratioKey} = $ratio;
        $allRatios = $self->ratios($ratioKey);
        if(!defined $allRatios) { $allRatios = []; }
        push @{$allRatios}, [$sKv->[0], $ratio];
      }
    }
  }
}

#@param $statsHref; the hash ref that holds the numerator & denominator,
#and where the ratio is stored
#this does not recurse
#@return void
sub _recursiveCalc
{
  my ($self, $numKey, $denomKey, $statsHref, $numCount, $denomCount) = @_;
  
  my $statKey = $self->statsKey;
  my $countKey = $self->countKey;
  for my $statVal (values %$statsHref)
  {
    my $hasNumer = $self->_isHashRef($statVal, [$numKey, $statKey, $countKey] );
    my $hasDenom = $self->_isHashRef($statVal, [$denomKey, $statKey, $countKey] );
    
    if(!($hasNumer && $hasDenom) ) 
    {
      return ($numCount, $denomCount); 
    }
    if($hasNumer) {
      $numCount += $statVal->{$numKey}{$statKey}{$countKey};
    }
    if($hasDenom) {
      $denomCount += $statVal->{$denomKey}{$statKey}{$countKey};
    }

    ($numCount, $denomCount) = 
      $self->_recursiveCalc($numKey, $denomKey, $statVal, $numCount, $denomCount);
  }
  return ($numCount, $denomCount);
}

sub ratioKeys
{
  my $self = shift;
  my $ratioKey = shift;
  return map { $_->[0] } $self->ratios($ratioKey);
}

sub ratioValues
{
  my $self = shift;
  my $ratioKey = shift;
  return map { $_->[1] } $self->ratios($ratioKey);
}

###########Private#####################
# requires non-0 value for denominator
# 9999 is inf; case when no transversions; actual 'Infinity' is platform-specific
sub _calcRatio
{
  my ($numerator, $denominator) = @_;
  if(!($numerator && $denominator) ) { return undef; }
  elsif($numerator && !$denominator) {return 9999; } #safe inf 
  elsif(!$numerator) {return 0; }
  return $numerator/$denominator;
}

sub _isHashRef
{
  my ($self, $mRef, $keysAref) = @_;
  if(ref $mRef ne 'HASH'){ return 0;}
  for my $key (@{$keysAref} )
  {
    if(!defined $mRef->{$key} ) { return 0; }
    $self->_isHashRef($mRef->{$key})
  }
}

no Moose::Role;
1;