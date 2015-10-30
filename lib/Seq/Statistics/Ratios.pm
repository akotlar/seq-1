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
requires 'statsKv';
requires 'debug';

has ratioFeaturesRef => (
  is      => 'ro',
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
sub _buildRatioFeaturesRef {
  my $self = shift;
  return {
    Silent => ['Replacement','Silent:Replacement'],
    Transitions => ['Transversions', 'Transitions:Transversions'],
  };   
}
# each key should be the ratio name, each value all ratios for that name
# one ratio per sample
has ratiosHref => (
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

sub makeRatios {
  my $self= shift;

  my $statsKey = $self->statsKey;
  my ($ratio, $allRatios, $ratioKey, $numerator, $denominator);
  
  for my $rKv ($self->ratioFeaturesKv) { #return [denom.[denom, ratioKey]]
    for my $sKv ($self->statsKv) { #return [sampleID.{HashRef}]
      if($self->debug) {
        say "checking ratioNumerator {$rKv->[0]}, denom {$rKv->[1][0]},
        statsKv key {$sKv->[0]} and value:";
        p $sKv->[1];
      }

      ($numerator, $denominator) = 
        $self->_recursiveCalc($rKv->[0], $rKv->[1][0], $sKv->[1] );

      say "Numerator: $numerator. Denominator: $denominator" if $self->debug;
      
      $ratio = _calcRatio($numerator, $denominator);
      if(defined $ratio) {
        $ratioKey = $rKv->[1][1];
        $sKv->[1]{$self->statsKey}{$ratioKey} = $ratio;
        if(!$self->hasRatios($ratioKey) ) { $self->setRatios($ratioKey, []); }
        push @{$self->getRatios($ratioKey) }, [$sKv->[0], $ratio];
        say "Pushing $ratioKey ratio, for {$sKv->[0]}, val $ratio" if $self->debug;
      }
    }
  }
}

#@param $statsHref; the hash ref that holds the numerator & denominator,
#and where the ratio is stored
#this does not recurse
#@return void
sub _recursiveCalc {
  my ($self, $numKey, $denomKey, $statsHref, $nCount, $dCount) = @_;
  
  my $statKey = $self->statsKey;
  my $countKey = $self->countKey;

  for my $key (keys %$statsHref) {
    if($key eq $statKey || $key eq $countKey){next; }
    #TODO: also check if one of the ratio keys
    my $statVal = $statsHref->{$key};

    if($self->debug) {
      say "key in recursiveCalc is " . $key;
      say "val in recursiveCalc is";
      p $statVal;
    }
    
    #less than 2 because need at least a statKey => {countKey => val}
    if(ref $statVal ne 'HASH'){return ($nCount, $dCount); }

    if($self->debug) {
      say "checking stat value for key $key";
      p $statVal;
    }
    
    my ($numer, $denom);
    if($key eq $numKey) {
      $numer = $self->_nestedVal($statVal, [$statKey, $countKey] );
    }
    elsif($key eq $denomKey) {
      $denom = $self->_nestedVal($statVal, [$statKey, $countKey] );
    } 

    #if one defined, we found the right level, but by chance a missing value
    #_calcRatio will handle that
    if(!(defined $numer || defined $denom) ) {
      ($nCount, $dCount) = 
        $self->_recursiveCalc($numKey, $denomKey, $statVal, $nCount, $dCount);
    } else {
      if(defined $numer){$nCount += $numer; }
      if(defined $denom){$dCount += $denom; }
      
      if($self->debug) {
        say "adding to nCount: $numer; total $nCount, to dCount: $denom; total $dCount";
      }
    }
  }
  return ($nCount, $dCount);
}

###########Private#####################
# requires non-0 value for denominator
# 9999 is inf; case when no transversions; actual 'Infinity' is platform-specific
sub _calcRatio {
  my ($numerator, $denominator) = @_;
  if(!($numerator || $denominator) ) {return undef; }
  #handle infinity by any string that doesn't cast to a number
  #since infinity handling is platform specific, and we won't be using math
  elsif($numerator && !$denominator) {return -9; } 
  elsif(!$numerator) {return 0; }
  return $numerator/$denominator;
}

#order of keys in $keysAref matters; rotate 90 degrees clockwise and look down
sub _nestedVal {
  my ($self, $mRef, $keysAref) = @_;

  if($self->debug) {
    say "in _nestedVal mRef is";
    p $mRef;
    say "and keys are ";
    p $keysAref;
    say "and num keys left is" . scalar @$keysAref;
  }
  
  if(@$keysAref == 0) {
    return $mRef;
  }
  if(ref $mRef ne 'HASH'){ return undef;}

  my $key = shift @$keysAref;
  if(!defined $mRef->{$key} ) {return undef;}
  # say "mref has key $key, next loop";

  $self->_nestedVal($mRef->{$key}, $keysAref);
}

no Moose::Role;
1;
