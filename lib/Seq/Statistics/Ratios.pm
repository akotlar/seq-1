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
    getRatios => 'get',
    hasRatios => 'defined',
    setRatios => 'set',
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
      say "checking ratioNumerator {$rKv->[0]}, denom {$rKv->[1][0]},
       statsKv key {$sKv->[0]} and value:";
      p $sKv->[1];
      ($numerator, $denominator) = 
        $self->_recursiveCalc($rKv->[0], $rKv->[1][0], $sKv->[1] );

      say "We got from recursiveCalc numerator: $numerator and denominator: $denominator";
      $ratio = _calcRatio($numerator, $denominator);
      if(defined $ratio)
      {
        $ratioKey = $rKv->[1][1];
        $sKv->[1]{$self->statsKey}{$ratioKey} = $ratio;
        if(!$self->hasRatios($ratioKey) ) { $self->setRatios($ratioKey, []); }
        push @{$self->getRatios($ratioKey) }, [$sKv->[0], $ratio];
        say "we are pushing ratio for $ratioKey, for {$sKv->[0]} val $ratio";
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
  my ($self, $numKey, $denomKey, $statsHref, $nCount, $dCount) = @_;
  
  my $statKey = $self->statsKey;
  my $countKey = $self->countKey;
  say "in recurise calc statKey is $statKey and countKey is $countKey";
  for my $key (keys %$statsHref)
  {
    my $statVal = $statsHref->{$key};
    if(ref $statVal ne 'HASH'){ return ($nCount, $dCount); }

    say "checking stat value for key $key";
    p $statVal;

    my ($numer, $denom);
    if($key eq $numKey || $key eq $denomKey)
    {
      $numer = $self->_nestedVal($statVal, [$statKey, $countKey] );
      $denom = $self->_nestedVal($statVal, [$statKey, $countKey] );
    }   
    say "Numerator is $numer";
    say "Denominator is $denom";

    #if one defined, we found the right level, but by chance a missing value
    #_calcRatio will handle that
    if(!(defined $numer || defined $denom) )
    {
      ($nCount, $dCount) = 
        $self->_recursiveCalc($numKey, $denomKey, $statVal, $nCount, $dCount);
    } 
    else
    {
      if(defined $numer){$nCount += $numer; }
      if(defined $denom){$dCount += $denom; }
    
      say "nCount is $nCount";
      say "dCount is $dCount";
    }
  }
  return ($nCount, $dCount);
}

sub ratioKeys
{
  my $self = shift;
  my $ratioKey = shift;
  return map { $_->[0] } $self->getRatios($ratioKey);
}

sub ratioValues
{
  my $self = shift;
  my $ratioKey = shift;
  return map { $_->[1] } $self->getRatios($ratioKey);
}

###########Private#####################
# requires non-0 value for denominator
# 9999 is inf; case when no transversions; actual 'Infinity' is platform-specific
sub _calcRatio
{
  my ($numerator, $denominator) = @_;
  #say "_calcRatio called with numerator $numerator && denominator: $denominator";
  if(!($numerator || $denominator) ) {return undef; }
  elsif($numerator && !$denominator) {return 9999; } #safe inf 
  elsif(!$numerator) {return 0; }
  return $numerator/$denominator;
}

#order of keys in $keysAref matters; rotate 90 degrees clockwise and look down
sub _nestedVal
{
  my ($self, $mRef, $keysAref) = @_;
  if(keys %$mRef < @$keysAref) {return undef; } #definitely don't have nec. depth
  if(@$keysAref == 0)
  {
    say "returning $mRef from _nestedVal";
    return $mRef;
  }
  if(ref $mRef ne 'HASH'){ return undef;}

  say "in _nestedVal checking keys";
  p $keysAref;
  say "in _nestedVal checked mref";
  p $mRef;

  my $key = shift @$keysAref;
  if(!defined $mRef->{$key} ) {return undef;}
  say "mref has key $key, next loop";
  say "after shift keys are";
  p $keysAref;
  $self->_nestedVal($mRef->{$key}, $keysAref);
}

no Moose::Role;
1;
