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
    ratios => 'accessor',
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
  my ($ratio, $ratioKey, $numerator, $denominator);
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
        push @{$self->allRatios($ratioKey) }, [$sKv->[0], $ratio];
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
  
  for my $statVal (values %$statsHref)
  {
    if(ref $statVal ne 'HASH') { return ($numCount, $denomCount); }
      
    if(defined $statVal->{$numKey} && defined $statVal->{$denomKey} )
    {
      # avoid autovivification 
      if(defined $statVal->{$numKey}{$self->statsKey} && 
      defined $statVal->{$numKey}{$self->statsKey}{$self->countKey} ) {
        $numCount += $statVal->{$numKey}{$self->statsKey}{$self->countKey};
      }
      
      if(defined $statVal->{$denomKey}{$self->statsKey} && 
      defined $statVal->{$denomKey}{$self->statsKey}{$self->countKey} ) {
        $denomCount += $statVal->{$denomKey}{$self->statsKey}{$self->countKey};
      }
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

no Moose::Role;
1;