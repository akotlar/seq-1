#!/usr/bin/env perl
=head1 NAME

Statistics::StatisticsCalculator

=head1 SYNOPSIS
Calculates Transition:Transversion, SiteType:SiteTypePartner Ratios (default Silent:Replacement)
=head1 DESCRIPTION

=head1 AUTHOR
Alex Kotlar <akotlar@emory.ed>
based on David Cutler's transversion:transition calculator
=head1 Logic of Transition & Transversion counts:

If the genotype is an acceptable transition or transversion, it will be recorded always in the sample's summary statistics hash
Then, for each siteType and siteCode of that sample that is also in allowedTypesRef and allowedCodesRef respectively, the genotype
will be recorded.
So in some cases, the total number of transitiosn and transversions for a sample will not reflect the # of transitions and transversion summed from
siteTypes or siteCodes
====

=cut
package StatisticsCalculator;

use Moose;
extends 'StatisticsBase';

use File::Basename;   
use lib dirname(__FILE__);

use Data::Dumper;
use Hash::Merge;

#############################################################################
# Public Methods
#############################################################################

#
#record Transitions and Transversions
#@param $siteType (str or array) ex: SNP, MESS, DEL, INS
#@param $siteCode (str or array) ex: Replacement, Intronic, Silent
#@param $referenceAllele (str) ex: 'A'
#@param $sampleGenotypesRef (HASH reference) : ex { 'Y' : [sample1id,sample2id,sample3id], 'C' : [sample1id] }
#@return HASH : in format 'sampleID' => { transition: int, transversion:int, 'siteType1' => { transition: int, transversion:int, siteCode1' => { transition: int, transversion:int}} } 
#
sub recordTransitionTransversion
{ 
  my $self = shift;
  my ($siteType,$siteCode,$referenceAllele,$sampleGenotypesRef) = @_; #siteCode is Intronic, Replacement, etc ; $varTypeCounts is $var_type_counts {}
  my %annotateThis = ($siteType => 0,$siteCode => 0);
  my $isTransition = 0;
  my $transitionKey;

  $siteType = $self->_makeUnique($siteType); #may be an array; precautionary, this may be removed if never possible to have array
  $siteCode = $self->_makeUnique($siteCode); #may be an array

  foreach my $genotype (keys %$sampleGenotypesRef) #%sampleGenotypesRef expected to have : { $someGenotype => [sampleID#1,sampleID#2...sampleID#N] }
  {
    if( !($genotype eq $referenceAllele) && !( exists( $self->disallowedTypesRef->{$genotype} ) ) )
    {
      if( exists( $self->_transitionTypesHref->{$genotype} ) || exists( $self->_transitionTypesHref->{$referenceAllele.$genotype} ) )
      {
        $isTransition = 1;
      }
      $transitionKey = $self->_getTransitionTransversionKeys($isTransition);

      foreach my $sampleID ( @{ $sampleGenotypesRef->{$genotype} } )
      { 
        my $sampleHashRef = \%{ $self->statisticRecordRef->{$sampleID} };  #if we just copy the ref, and $self->statisticRecordRef->{$sampleID} doesn't exist, won't be vivified, so wrap in \%{ratioKeys}

        $sampleHashRef->{$self->statisticsKey}->{$transitionKey}++; #top level statistic gets stored in $statisticsKey to avoid confusion

        if( exists( $self->allowedTypesRef->{ uc($siteType) } ) )
        {
          my $sampleSiteTypeHashRef = \%{ $sampleHashRef->{$siteType} };

          $sampleSiteTypeHashRef->{$self->statisticsKey}->{$transitionKey}++;

          if( exists( $self->allowedCodesRef->{ uc($siteCode) } ) ) #if we ever decided to allow recording transition for heterozygous site codes
          {
            $sampleSiteTypeHashRef->{$siteCode}->{$self->statisticsKey}->{$transitionKey}++;
          }
        }
      }
    }
  }
  return $isTransition;
}

#
#Calculate the ratios from some counts
#
#expects format like {'sampleID' => { 'transition' => (int), transversions => int $siteType => { transitions => int, transversions => int, { 'siteCode1' => { transitions => int, transversions => int }, 'siteCode2' => same as siteCode1 }}}
sub calculateStatistics
{
  my $self = shift;
  my ($masterHashReference, $siteTypeCountKey) = @_; #$siteTypeCountKey is optional
  my %ratioCollection; #hash of array ref { 'ratioName' => [1,2,3,...N-1] }

  foreach my $sampleID (keys %$masterHashReference)
  {
    my $sampleStatisticsHashRef = \%{ $self->statisticRecordRef->{$sampleID}->{$self->statisticsKey} };
    my ($transitionKey,$transversionKey,$trTvRatioKey) = $self->_getTransitionTransversionKeys();

    #the sampleID level should get statistics placed in the $statisticsKey to avoid confusion
    my $trTvRatio = $self->_calculateRatio($transitionKey,$transversionKey,$sampleStatisticsHashRef);    

    $sampleStatisticsHashRef->{$trTvRatioKey} = $trTvRatio;

    push( @{ $ratioCollection{$trTvRatioKey} },$trTvRatio ); #record all the summary tr:tv ratios

    foreach my $siteType ( keys %{ $masterHashReference->{$sampleID} } )
    { 
      foreach my $siteCode ( keys %{ $masterHashReference->{$sampleID}->{$siteType} } )
      {
        $self->_calculateSiteStatistic($sampleID,$masterHashReference,$siteType,$siteCode,$siteTypeCountKey);
      }
    }

    #and calculate summary statistics on siteTypes and siteCodes
    foreach my $siteCodeNumeratorKey (keys %{$self->siteTypeRatiosOrganizerRef})
    { 
      my ($siteCodeDenominatorKey,$siteCodeRatioKey) = $self->_getSiteDenominatorRatioKeys($siteCodeNumeratorKey);   
      my $ratio = $self->_calculateRatio($siteCodeNumeratorKey,$siteCodeDenominatorKey,$sampleStatisticsHashRef);

      $sampleStatisticsHashRef->{$siteCodeRatioKey} = $ratio;  

      push( @{ $ratioCollection{$siteCodeRatioKey} },$ratio );  
    }
  }

  if(keys %ratioCollection)
  {
    $self->_calculatePercentiles(\%ratioCollection);

    ##add percentiles above sample keys in the result hierarchy
    $self->_qcOnPercentiles($masterHashReference);
  }

  $self->_storeExperimentMetaData();
}

#
#merge the calling package's hash with the statistics recorded here
#
#conservative; only merges on keys found in $masterHashReference
###default: Hash::Merge::set_set_behavior('LEFT_PRECEDENT');
sub leftHandMergeStatistics
{
  my $self = shift;
  my $masterHashReference = shift;

  Hash::Merge::merge($masterHashReference,$self->statisticRecordRef); #returns hash reference
}

__PACKAGE__->meta->make_immutable;

1;
=head1 COPYRIGHT

Copyright (c) 2014 Alex Kotlar (<alex.kotlar@emory.edu>). All rights
reserved.

=head1 LICENSE