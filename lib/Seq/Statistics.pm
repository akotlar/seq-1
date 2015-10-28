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
package Seq::Statistics;

use Moose;
extends 'Seq::Statistics::Base';
with 'Seq::Statistics::Record';
use namespace::autoclean;

use Seq::Statistics::Percentiles;

use File::Basename;   
use lib dirname(__FILE__);

has statsKey =>
( 
  is      => 'ro',
  isa     => 'Str',
  default => 'statistics',
  required => 1,
);
has percentilesKey =>
(
  is      => 'ro',
  isa     => 'Str',
  default => 'percentiles',
  required => 1,
);
has ratioKey =>
( 
  is      => 'ro',
  isa     => 'Str',
  default => 'ratios',
  required => 1,
);
has qcFailKey =>
( is      => 'ro',
  isa     => 'Str',
  default => 'qcFail',
  required => 1,
);
has debug =>
( is      => 'ro',
  isa     => 'Int',
  default => '0',
);

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
sub summarize
{ 
  my $self = shift;
  my ($percentilesHref, $samples, $ratios, $samplesAref, $ratiosAref, $destHref);

  $self->makeRatios;

  if($self->hasNoRatios) {
    #message
    return;
  }

  for my $kv ($self->allRatiosKv)
  {
    if(!$self->hasRatioCollection($kv->[0]) ) {next;}

    $percentilesHref = Seq::Statistics::Percentiles->new(
      ratioName => $kv->[0],
      ratios => $kv->[1],
      qcFailKey => $self->qcFailKey,
    );

    $percentilesHref->makePercentiles;

    if($percentilesHref->hasNoPercentiles) {next;}
   
    $destHref = $self->getStat($self->statsKey);

    $percentilesHref->storePercentiles($destHref);

    #order of sample keys must match ratio values
    $percentilesHref->qc(
      $self->oneRatioKeys($kv->[0] ), $self->oneRatioVals($kv->[0] ), $destHref
    )
  }
}
__PACKAGE__->meta->make_immutable;
1;
=head1 COPYRIGHT

Copyright (c) 2014 Alex Kotlar (<alex.kotlar@emory.edu>). All rights
reserved.

=head1 LICENSE