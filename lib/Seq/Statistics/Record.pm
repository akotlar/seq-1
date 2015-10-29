package Seq::Statistics::Record;

use 5.10.0;
use Moose::Role;
use strict;
use warnings;

use Carp qw/cluck confess/;
use List::MoreUtils qw(first_index);
use syntax 'junction';

use DDP;

requires 'deconvoluteIUPAC';
requires 'badGenos';
requires 'statsKey';
requires 'statsRecord';
requires 'debug';

has countKey => 
(
  is => 'rw',
  isa => 'Str',
  lazy => 1,
  default => 'count',
);

#href because the value corrsponds to the indices of _transitionTranvserionKeysAref
has _transitionTypesHref =>
( is      => 'ro',
  isa     => 'HashRef[Int]',
  traits  => ['Hash'],
  handles => {
    isTr => 'get',
  },
  default => sub { return {AG => 1,GA => 1,CT => 1,TC => 1,R => 1,Y => 1} },
  lazy => 1,
  init_arg => undef 
);

has _transitionTransversionKeysAref =>
( is      => 'ro',
  isa     => 'ArrayRef[Str]',
  traits  => ['Array'],
  handles => {
    trTvKey => 'get',
  },
  default => sub{ ['Transversions','Transitions'] },
  lazy => 1,
  init_arg => undef,
);

# at every level in the has, record whether transition or transversion
# assumes that only non-reference alleles are passed, hence it is a role
sub record
{
  my ($self, $sampleIDgenoHref, $annotationsAref, $refAllele,
    $varType, $genomicType) = @_;
  my ($geno, $deconvolutedGeno, @countedCombos, $combo, $minorAllele,
    $annotationType, $sampleStats, $trTvKey);

  for my $sampleID (keys %$sampleIDgenoHref)
  {
    $geno = $sampleIDgenoHref->{$sampleID};

    #in case not passed carriers/hom mut's
    if($geno eq $refAllele|| $self->badGenos(sub{$_ eq $geno} ) > -1 ) {next;} 
    
    $deconvolutedGeno = $self->deconvoluteIUPAC($geno);

    for my $annotationHref (@$annotationsAref)
    {
      $minorAllele = $annotationHref->minor_allele;

      # if it's an ins or del, there will be no deconvolutedGeno
      if($geno ne $minorAllele && index($deconvolutedGeno, $minorAllele) == -1) {next;}
     
      $annotationType = $annotationHref->annotation_type;

      # say "annotation type is $annotationType";
      $combo = $minorAllele. $annotationHref->annotation_type;
      # say "combo is $combo"; say "countedCombos are"; p @countedCombos;

      #count each allele/feature combo one to fairly attribute multi-allelic variants
      #to samples that have one of the minor alleles but not the other (when both represented)
      if(any(@countedCombos) eq $combo) {next;}

      push @countedCombos, $combo;

      if(!$self->hasStat($sampleID) ) {  $self->setStat($sampleID, {}); }

      # if deconvolutedGeno falsy, it's not a SNP, can't have a tr or tv
      $trTvKey = $deconvolutedGeno ? $self->_getTr($refAllele, $geno) : undef;

      $self->storeTrTvAndCount([$varType, $genomicType, $annotationType],
        $self->getStat($sampleID), $trTvKey);
    }
  }
  # if($self->debug) {
  #   say "Stat record is";
  #   p $self->statsRecord;
  # }
}

#topTargetHref remains the top level hash, always gets transitions/transversion record
#because we want genome-wide tr:tv
#insertions and deletions don't have transitions and transversions, so check for that
sub storeTrTvAndCount
{
  my ($self, $featuresAref, $topTargetHref, $trTvKey, $targetHref) = @_;
  if(!@$featuresAref) { return };

  my $feature = shift @$featuresAref;
  $targetHref = defined $targetHref ? \%{$targetHref->{$feature} } : $topTargetHref;
  
  #transitions are unique, they are the only StatsCalculator created feature
  #they should only be inserted in a single locaiton, else they'll be counted
  #by sum(n*tr_i)
  if(defined $trTvKey) {
    $topTargetHref->{$trTvKey}{$self->statsKey}{$self->countKey} += 1;
  }
  $targetHref->{$self->statsKey}{$self->countKey} += 1;

  $self->storeTrTvAndCount($featuresAref, $topTargetHref, $trTvKey, $targetHref);
}

sub _getTr
{
  my ($self, $refAllele, $geno) = @_;
  return $self->trTvKey(int(!!($self->isTr($geno) || $self->isTr($refAllele.$geno) ) ) );
}

no Moose::Role;
1;
