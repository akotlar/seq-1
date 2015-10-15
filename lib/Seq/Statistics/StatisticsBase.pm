#!/usr/bin/env perl
=head1 NAME
Snpfile::StatisticsBase
=head1 SYNOPSIS
Provides variables, private functions for StatisticsCalculator.pm
=head1 DESCRIPTION

=head1 AUTHOR

Alex Kotlar <akotlar@emory.ed>

=head1 Types considered
SNP, MESS, LOW
- INS & DEL are treated as SNP
=cut

package StatisticsBase;

use Modern::Perl '2013';
use Moose;
  with 'MooseX::SimpleConfig'; #all constructor arguments can be overriden by passing the constructor (during "new") : {configfile=>'path/to/yamlfile.yaml'} with appropriate key:value pairs 
  with 'MooseX::Getopt'; #allows passing command line args, including -configfile, when used with StatisticsCalculator->new_with_optinos()
use Moose::Util::TypeConstraints;
use namespace::autoclean;#remove moose keywords after compilation
use YAML::XS;
use Try::Tiny;
use Data::Dumper;
use Hash::Merge;
use POSIX;
use Carp qw(cluck confess);
use Cwd;
use File::Basename;   

my $rq = eval #optional modules
{
  require threads;
  threads->import();

  require threads::shared;
  threads::shared->import();
  1;
};

#############################################################################
# Subtypes
#############################################################################
subtype 'ExperimentType',
as 'Str',  
where { $_ eq 'exome' || $_ eq 'genome' };

#############################################################################
# Non required vars passable to constructor during new 
# All can be passed either by new( {varName1:value,...} ) or new( {configfile=>'path/to/yamlfile.yaml'} ) 
#############################################################################
has assembly => 
(
  is  => 'ro',
  isa => 'Str',
  predicate => 'has_assembly'
);

has allowedTypesRef =>
( is      => 'ro',
  isa     => 'HashRef[Int]',
  builder => '_buildAllowedTypesRef'
);

has allowedCodesRef =>
( is      => 'ro',
  isa     => 'HashRef[Int]',
  builder => '_buildAllowedCodesRef'
);

has disallowedTypesRef =>
( is      => 'ro',
  isa     => 'HashRef[Int]',
  builder => '_buildDisallowedTypesRef'
);

has confidenceIntervalfailMessage =>
( is      => 'ro',
  isa     => 'Str',
  default => 'outside 2 standard deviations'
);

has verbose =>
( is      => 'ro',
  isa     => 'Int',
  default => '0'
);

has experimentType => 
(
  is  => 'ro',
  isa => 'Maybe[ExperimentType]', #ExperimentType or undef
  default => 'genome',
  predicate => 'has_experimentType'
);

#what siteTypeRatios we want to calculate
#ex: Silent => Replacement codes for Silent/Replacement ratio
#notice we don't uppercase, case found in the calling package's hashes must match this (or user must pass corrected key:values in constructor)
#the ratios will always be named "key:value"
has siteTypeRatiosOrganizerRef =>
( is      => 'ro',
  isa     => 'HashRef[ArrayRef[Str]]',
  builder => '_buildSiteTypeRatiosOrganizerRef'
);

#if the user supplies an experiment type, we can include expected ratio values in the experiment statistics summary
has expectedValuesRef =>
( is      => 'rw',
  isa     => 'Maybe[HashRef]', #hashref or undefined
  lazy => '1',
  builder => '_buildExpectedValuesRef'
);

#all percentiles investigated
has percentilesRef =>
( is      => 'ro',
  isa     => 'ArrayRef[Num]',
  default => sub{ [.05, .50, .95] },
  predicate => 'has_confidenceIntervalRef'
);

#############################################################################
# Vars not passable to constructor (private vars)
#############################################################################
has _transitionTypesHref =>
( is      => 'ro',
  isa     => 'HashRef[Int]',
  builder => '_buildTransitionTypesRef',
  init_arg => undef 
);

has _transitionTransversionKeysAref =>
( is      => 'ro',
  isa     => 'ArrayRef[Str]',
  builder => '_buildTransitionTransversionKeysAref',
  init_arg => undef 
);

has statisticsKey =>
( is      => 'ro',
  isa     => 'Str',
  default => 'statistics',
  init_arg => undef 
);

has qcFailKey =>
( is      => 'ro',
  isa     => 'Str',
  default => 'qcFail',
  init_arg => undef 
);

has expectedKey =>
( is      => 'ro',
  isa     => 'Str',
  default => 'expected',
  init_arg => undef 
);

has percentilesKey =>
(
  is      => 'ro',
  isa     => 'Str',
  default => 'percentiles',
  init_arg => undef 
);

#we store the ratio keys (like Transition:Transversion) in the top level statistic for the experiment in allRatiosKey : [key1,key2,key3, etc]
has allRatiosKey =>
( is      => 'ro',
  isa     => 'Str',
  default => 'ratioKeys',
  init_arg => undef 
);

#keeper of our statistics; can be many hashrefs deep
has statisticRecordRef => 
(
  is  => 'rw',
  isa => "HashRef",
  default => sub{ {} },
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

#############################################################################
# Default value builder functions
#############################################################################
sub _buildTransitionTypesRef #this should live in yml
{
  return {AG => 1,GA => 1,CT => 1,TC => 1,R => 1,Y => 1}; #R is IUPAC AG, Y is IUPAC CT
}

sub _buildAllowedTypesRef #this should live in yml
{
  return {SNP => 1,MULTIALLELIC => 1};
}

sub _buildAllowedCodesRef
{
  return {Silent => 1,Replacement => 1}
}

# numeratorKey=>[denominatorKey,ratioKey] 
sub _buildSiteTypeRatiosOrganizerRef
{
  return {Silent => ['Replacement','Silent:Replacement']};   
}

sub _buildDisallowedTypesRef
{
  return {N=>1};
}

sub _buildTransitionTransversionKeysAref 
{ 
  return ['Transversions','Transitions','Transitions:Transversions'];
}

sub _buildExpectedValuesRef
{
  my $self = shift;

  if( !$self->has_assembly || !$self->has_experimentType)
  {
    return undef;
  }
  
  try #config file may not have the expected values, just tell the user
  {
    say dirname(__FILE__).'/config/StatisticsCalculator/expectedValues.yml';
    my $config = YAML::XS::LoadFile( dirname(__FILE__).'/config/StatisticsCalculator/expectedValues.yml' );

    if( exists( $config->{$self->assembly} ) && exists( $config->{$self->assembly}->{$self->experimentType} ) ) #prevent autovivify
    {
      print "Expected Values:\n" if $self->verbose; print Dumper( $config->{$self->assembly}->{$self->experimentType} ) if $self->verbose;
      
      return $config->{$self->assembly}->{$self->experimentType};
    }
  }
  catch
  {
    cluck $_; #don't die, we may not have any expected values
    return undef;
  }
}

#############################################################################
# Private Methods
#############################################################################

sub _calculateSiteStatistic
{
  my $self = shift;
  my ($sampleID,$masterHashReference,$siteType,$siteCode,$siteTypeCountKey) = @_; 

  if( !defined($siteType) || !defined($sampleID) || !defined($masterHashReference) || !defined($siteCode) )
  {
    confess "calculateSiteTypeStatistic executed but missing parameters, line ~272 StatisticsCalculator.pm";
  }  

  if( !$self->allowedTypesRef->{ uc($siteType) } )
  {
    return;
  }
  my $sampleHashRef = \%{ $self->statisticRecordRef->{$sampleID} };
  
  my $siteTypeHashRef = \%{ $sampleHashRef->{$siteType} };
  my $siteCodeHashRef = \%{ $sampleHashRef->{$siteType}->{$siteCode} };
   
  my ($transitionKey,$transversionKey,$trTvRatioKey) = $self->_getTransitionTransversionKeys();

  my ($siteCodeDenominatorKey,$siteCodeRatioKey) = $self->_getSiteDenominatorRatioKeys($siteCode);

  my $siteTypeHashStatsRef = \%{ $siteTypeHashRef->{ $self->statisticsKey} };
  my $siteTypeTrTv = $self->_calculateRatio($transitionKey,$transversionKey,$siteTypeHashStatsRef);
  $siteTypeHashStatsRef->{$trTvRatioKey} = $siteTypeTrTv if defined $siteTypeTrTv;

  # my $siteCodeHashStatsRef = \%{ $siteCodeHashRef->{ $self->statisticsKey} };
  # my $siteCodeTrTv = $self->_calculateRatio($transitionKey,$transversionKey,$siteCodeHashStatsRef); 
  # $siteCodeHashStatsRef->{$trTvRatioKey} = $siteCodeTrTv if defined $siteCodeTrTv;
  
  #some siteCodes aren't allowed
  if($siteCodeDenominatorKey) #calculate siteType, siteCode ratios, passed hash to $self->_calculateRatio is always 1 up in the heirarchy 
  {
    my $siteTypeHashRef = \%{ $masterHashReference->{$sampleID}->{$siteType} };

    #calculate the summary statistic
    my $summaryStat = $self->_calculateRatio($siteCode,$siteCodeDenominatorKey,$siteTypeHashRef,$siteTypeCountKey);

    if (defined $summaryStat) {
      my $statisticsHashRef = \%{ $sampleHashRef->{$siteType}->{$self->statisticsKey} };
      $statisticsHashRef->{$siteCodeRatioKey} = $summaryStat;
    }
    
    #and store the values for the overall sample, for ratio later
    my $numeratorVal = $self->_getValue($siteCode,$siteTypeHashRef,$siteTypeCountKey);
    my $denominatorVal = $self->_getValue($siteCodeDenominatorKey,$siteTypeHashRef,$siteTypeCountKey);

    my $summaryStatisticsHashRef;

    if($numeratorVal || $denominatorVal) {
      $summaryStatisticsHashRef = \%{ $sampleHashRef->{ $self->statisticsKey} };
    }

    if($numeratorVal)
    {
      $summaryStatisticsHashRef->{$siteCode} += $numeratorVal;

      print "Numerator val is: $numeratorVal for siteType $siteType with siteCode $siteCode\n" if $self->verbose;
    }
    
    if($denominatorVal)
    {
      $summaryStatisticsHashRef->{$siteCodeDenominatorKey} += $denominatorVal;

      print "Denominator val is: $denominatorVal for siteType $siteType with siteCode $siteCode\n" if $self->verbose;
    }
  }
}

#
#Calculate any ratio
#If denominator missing, records 1, if numerator missing records 0, since we often won't record 0 counts
#
sub _calculateRatio
{
  my $self = shift;
  my ($numeratorKey,$denominatorKey,$hashReference,$subKey) = @_;

  my $existsNumeratorEntry = exists( $hashReference->{$numeratorKey} );
  my $existsDenominatorEntry = exists( $hashReference->{$denominatorKey} );
  
  my ($numerator,$denominator);

  if(!$existsNumeratorEntry && !$existsDenominatorEntry )
  {
    cluck "_calculateRatio given wrong numeratorKey or denominatorKey in StatisticsCalculator.pm " if $self->verbose;
  }
  elsif(!$subKey)
  {
    if($existsNumeratorEntry)
    {
      $numerator = $hashReference->{$numeratorKey};
    }

    if($existsDenominatorEntry)
    {
      $denominator = $hashReference->{$denominatorKey};
    }
  }
  elsif($subKey)
  {     
    if( !exists($hashReference->{$numeratorKey}->{$subKey}) && !exists($hashReference->{$denominatorKey}->{$subKey}) )
    {
      cluck "_calculateRatio given wrong subKey in StatisticsCalculator.pm" if $self->verbose;
    }
    else
    {
      if($existsNumeratorEntry)
      {
        $numerator = $hashReference->{$numeratorKey}->{$subKey};
      }
      
      if($existsDenominatorEntry)
      {
        $denominator = $hashReference->{$denominatorKey}->{$subKey};
      }
    }
  }  

  if( !defined($numerator) && !defined($denominator) )
  {
    return undef; #if denominator not defined, the numerator makes up the entirety, for a binary system
  }
  elsif( !defined($denominator) )
  {
    return undef; #if denominator not defined, the numerator makes up the entirety, for a binary system
  }
  elsif( !defined($numerator) )
  {
    return 0; #if numerator not defined, the denominator makes up the entirety, for a binary system
  }
  return $numerator / $denominator;
}

sub _calculatePercentiles
{
  my $self = shift;
  my $ratioCollectionReference = shift;
  
  @{$self->percentilesRef} = sort{$a <=> $b} @{$self->percentilesRef}; #sort decimal percentiles ascending; are we ok with this side-effect , or better to copy the array?

  for my $ratioKey (keys %$ratioCollectionReference )
  { 
    @{ $ratioCollectionReference->{$ratioKey} } = sort{ $a <=> $b } @{ $ratioCollectionReference->{$ratioKey} }; #sort array ascending; are we ok with this side-effect , or better to copy the array?

    my @percentileValues;
    for my $percentile ( @{$self->percentilesRef} )
    {
      push @percentileValues, $self->_getPercentile($ratioCollectionReference->{$ratioKey},$percentile);
    }
    $self->ratioPercentilesRef->{$ratioKey}->{ $self->percentilesKey } = \@percentileValues;

    print "\nThe " . join(",",@{$self->percentilesRef}) ." percentiles of $ratioKey are ". join(",",@percentileValues) . "\n\n" if $self->verbose;
  }
}

sub _getPercentile #todo: check that percentiles between 0 and 1
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

sub _qcOnPercentiles
{
  my $self = shift;
  my $masterHashReference = shift;

  foreach my $ratioKey ( keys %{$self->ratioPercentilesRef} )
  { 
    my $thisRatioPercentilesRef = $self->ratioPercentilesRef->{$ratioKey}->{$self->percentilesKey};
    my $lowerPercentileValue = $thisRatioPercentilesRef->[0];
    my $upperPercentileValue = $thisRatioPercentilesRef->[-1];

    if(!defined($lowerPercentileValue) || !defined($upperPercentileValue) || scalar @$thisRatioPercentilesRef <= 1) #undefined value or length of array is 1
    {
      cluck "Improper ratioPercentilesRef found in StatisticsCalculator.pm";
      next;
    }
    ##for each sample record whether or not sample is within acceptable range
    foreach my $sampleID (keys %$masterHashReference)
    {
      if(!exists($self->statisticRecordRef->{$sampleID}))
      {
        cluck "Sample ID $sampleID not found in _qcOnPercentiles, StatisticsCalculator.pm";
        next;
      }
      my $sampleRatioValue = $self->statisticRecordRef->{$sampleID}->{$self->statisticsKey}->{$ratioKey};

      if( defined($sampleRatioValue) && ( $sampleRatioValue > $upperPercentileValue || $sampleRatioValue < $lowerPercentileValue) )
      {
        # not within confidence interval; failed QC
        $self->statisticRecordRef->{$sampleID}->{$self->statisticsKey}->{$self->qcFailKey}->{$ratioKey} = $self->confidenceIntervalfailMessage;

        $self->statisticRecordRef->{$self->statisticsKey}->{$self->qcFailKey}->{$sampleID}->{$ratioKey} = $self->confidenceIntervalfailMessage;  
      }
    }
  }
}

sub _storeExperimentMetaData
{
  my $self = shift;
  my $experimentStatisticsRef = $self->statisticRecordRef->{$self->statisticsKey};

  $self->_storeRatioKeysInHash($experimentStatisticsRef);

  $self->_storeExpectedValuesInHash($experimentStatisticsRef);

  $self->_storePercentilesInHash($experimentStatisticsRef);
}

sub _storeRatioKeysInHash #for easy retrieval / visualization in downstream scripts, primarily my webapp
{
  my $self = shift;
  my $storageHashRef = shift;
  my @siteRatioKeys = ();
  
  my $trTvRatioKey = $self->_getTransitionTransversionKeys(); #gets last item of returned array of transition,transversion keys

  foreach my $siteKey ( keys %{$self->siteTypeRatiosOrganizerRef} )
  {
    my $ratioKey = $self->_getSiteDenominatorRatioKeys($siteKey); 
    push @siteRatioKeys, $ratioKey;
  }
  push @siteRatioKeys, $trTvRatioKey;

  $storageHashRef->{$self->allRatiosKey} = \@siteRatioKeys;
}

sub _storeExpectedValuesInHash
{
  my $self = shift;
  my $storageHashRef = shift;

  if( defined($self->expectedValuesRef) )
  {
    $storageHashRef->{$self->expectedKey} = $self->expectedValuesRef;
  }
}

sub _storePercentilesInHash
{
  my $self = shift;
  my $storageHashRef = shift;
  my @percentilesRef = sort{$a <=> $b} @{$self->percentilesRef}; #get ascending order of percentiles

  foreach my $ratioKey ( keys %{$self->ratioPercentilesRef} )
  {
    my @thisRatioPercentiles =  @{ $self->ratioPercentilesRef->{$ratioKey}->{$self->percentilesKey} }; #should be sorted ascending

    my $experimentRatioPercentilessRef = \%{ $storageHashRef->{$ratioKey}->{$self->percentilesKey} }; #auto-vivify

    %$experimentRatioPercentilessRef = map { $percentilesRef[$_] => $thisRatioPercentiles[$_] } 0..$#thisRatioPercentiles;
  }
}

sub _makeUnique
{
  my $self = shift;
  my $recordReferenceOrPrimitive = shift;

  if(ref($recordReferenceOrPrimitive) eq 'ARRAY')
  {
    my %unique;

    for my $key (keys @$recordReferenceOrPrimitive)
    {
      $unique{$key} = 1;
    }
    return join(";",keys %unique);
  }
  elsif(ref($recordReferenceOrPrimitive) eq 'HASH')
  {
    confess "Record passed to Snpfile::StatisticsCalculator::makeUnique was hash, unsupported";
  } 
  return $recordReferenceOrPrimitive;
}

sub _getValue
{
  my $self = shift;
  my($key,$hashReference,$subKey) = @_;

  if($subKey)
  {
    return $hashReference->{$key}->{$subKey};
  }
  else
  {
    return $hashReference->{$key};
  }
}

#
# Purpose: attempt retrieve the transition and transversion keys
# @required $self->_transitionTransversionKeysAref == array(transversionName,transitionName,ratioName)
# @return array(str,str,str)  
#
sub _getTransitionTransversionKeys
{
  my ($self,$keyIndex) = @_;

  if( defined($keyIndex) )
  {
    return $self->_transitionTransversionKeysAref->[$keyIndex];
  }
  
  my $transitionKey = $self->_transitionTransversionKeysAref->[1];
  my $transversionKey = $self->_transitionTransversionKeysAref->[0];
  my $trTvRatioKey = $self->_transitionTransversionKeysAref->[2];

  return ($transitionKey,$transversionKey,$trTvRatioKey);
}

#
# Purpose: attempt retrieve the denominator and numerator keys for a given siteCode 
# @param $numeratorKey (str)
# @return array(str,str) or (undef,undef) if no denominatorKey found
#
sub _getSiteDenominatorRatioKeys
{
  my $self = shift;
  my $numeratorKey = shift;

  if( !exists($self->siteTypeRatiosOrganizerRef->{$numeratorKey}) )
  {
    return;
  }
  my $denominatorKey = $self->siteTypeRatiosOrganizerRef->{$numeratorKey}->[0];
  my $ratioKey = $self->siteTypeRatiosOrganizerRef->{$numeratorKey}->[1];

  return ($denominatorKey, $ratioKey);
}

__PACKAGE__->meta->make_immutable;

1;
=head1 COPYRIGHT

Copyright (c) 2014 Alex Kotlar (<alex.kotlar@emory.edu>). All rights
reserved.

=head1 LICENSE