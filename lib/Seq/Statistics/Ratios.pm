package Seq::Statistics::Ratios;
our $VERSION = '0.001';

use strict;
use warnings;
use Moose::Role;

use Carp qw(cluck confess);

requires 'statsKey';
requires 'ratioKey';
requires 'statsRecord';

has ratioFeaturesRef =>
( is      => 'ro',
  traits  => ['Hash'],
  isa     => 'HashRef[ArrayRef[Str]]',
  handles => {
    ratioNumerators => 'keys',
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
  for my $kv ($self->statsKv)
  {
    $self->_storeFeatureRatios($kv->[0], \%{$kv->[1]{$statsKey} } );
  }
}

#@param $statsHref; the hash ref that holds the numerator & denominator,
#and where the ratio is stored
#this does not recurse
#@return void
sub _storeFeatureRatios
{
  my ($self, $statsKey, $statsHref) = @_;
  my ($denomKeysAref, $ratioKey, $numerator, $denominator, $ratio, $ratiosHref);

  for my $numeratorKey (keys %$statsHref)
  {
    if(!$self->allowedNumerator($numeratorKey) ) {next;}
    $numerator = $statsHref->{$numeratorKey};
    #if numerator undefined, don't calc ratio; alt. we could calc as 0
    if(!defined $numerator) {next;}
    
    $denomKeysAref = $self->getDenomRatioKeys($numerator);
    if(!exists $statsHref->{$denomKeysAref->[0] } ) {next;}
    $denominator = $statsHref->{$denomKeysAref->[0] };
    #if denom undefined, don't calc ratio; alt. we could calc as inf, but meaning?
    if(!defined $denominator) {next;}
    
    $ratio = _calcRatio($numerator, $denominator);
    if(defined $ratio) {
      $ratioKey = $denomKeysAref->[1];
      $statsHref->{$ratioKey} = $ratio; 
      push @{$self->allRatios($ratioKey) }, [$statsKey, $ratio];
    }
  }
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
# 9999 is inf; case when no transversions
sub _calcRatio
{
  my ($numerator, $denominator) = @_;
  if(!$denominator) {return 9999; } #numerator may 
  if(!$numerator) {return 0; }
  return $numerator/$denominator;
}

no Moose::Role;
1;