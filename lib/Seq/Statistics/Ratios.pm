package Seq::Statistics::Ratios;
our $VERSION = '0.001';

use strict;
use warnings;
use Moose::Role;

use Carp qw(cluck confess);

require statisticRecordRef;

has _transitionTypesHref =>
( is      => 'ro',
  isa     => 'HashRef[Int]',
  traits  => ['Hash'],
  handles => {
    isTr => 'get',
  },
  default => sub { {AG => 1,GA => 1,CT => 1,TC => 1,R => 1,Y => 1} },
  init_arg => undef 
);

has _transitionTransversionKeysAref =>
( is      => 'ro',
  isa     => 'ArrayRef[Str]',
  traits  => ['Array'],
  handles => {
    trTvKey => 'get',
  },
  default => sub{ ['Transversions','Transitions','Transitions:Transversions'] },
  init_arg => undef 
);

#what siteTypeRatios we want to calculate
#ex: Silent => Replacement codes for Silent/Replacement ratio
#notice we don't uppercase, case found in the calling package's hashes must match this (or user must pass corrected key:values in constructor)
#the ratios will always be named "key:value"
has siteTypeRatiosOrganizerRef =>
( is      => 'ro',
  traits  => ['Hash'],
  isa     => 'HashRef[ArrayRef[Str]]',
  handles => {
    getSiteType => 'get',
  }
  builder => '_buildSiteTypeRatiosOrganizerRef'
);

# numeratorKey=>[denominatorKey,ratioKey] 
sub _buildSiteTypeRatiosOrganizerRef
{
  return {Silent => ['Replacement','Silent:Replacement']};   
}

sub recordTrTv
{
  my ($self, $hRef, $geno) = @_;

  my $transition = $self->trTvKey($self->isTr($geno) );
  for my $key (keys %$href)
  {
    if($href{$key}{})
    if(ref $href{$key} == 'HASH') {

    }
  }

  if($self->isTransition())
}

sub calculate
{
  my $self = shift;

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

no Moose::Role;
1;