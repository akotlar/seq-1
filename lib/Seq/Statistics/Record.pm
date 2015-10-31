package Seq::Statistics::Record;

use 5.10.0;
use Moose::Role;
use strict;
use warnings;

use Carp qw/cluck confess/;
use List::MoreUtils qw(first_index);
use syntax 'junction';

use DDP;

#provides deconvoluteGeno, hasGeno, isHomo, isHet
with 'Seq::Role::Genotypes', 'Seq::Role::Message';

requires 'isBadFeature';
requires 'statsKey';
requires 'statsRecord';
requires 'debug';

has countKey => (
  is => 'rw',
  isa => 'Str',
  lazy => 1,
  default => 'count',
);

#href because the value corrsponds to the indices of _transitionTranvserionKeysAref
has _transitionTypesHref => (
  is      => 'ro',
  isa     => 'HashRef[Int]',
  traits  => ['Hash'],
  handles => {
    isTr => 'get',
  },
  default => sub {return {AG => 1,GA => 1,CT => 1,TC => 1,R => 1,Y => 1} },
  lazy => 1,
  init_arg => undef 
);

has _transitionTransversionKeysAref => (
  is      => 'ro',
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
sub record {
  my ($self, $sampleIDgenoHref, $annotationsAref, $featuresAref, $refAllele) = @_;

  if(!(keys %$sampleIDgenoHref && @$annotationsAref 
  && @$featuresAref && defined $refAllele) ) {
    return; 
  }

  my ($geno, $dGeno, $annotationType, $sampleStats, $trTvKey, 
    $targetHref, $minorAllele, $aCount, @featuresMerged);

  #for now, analyze only 
  for my $sampleID (keys %$sampleIDgenoHref) {
    $geno = $sampleIDgenoHref->{$sampleID};
    if($self->hasGeno($geno, $refAllele) ) {next;} #require IUPAC geno, or D,I,E,H

    if(!$self->hasStat($sampleID) ) {$self->setStat($sampleID, {} ); }
    $targetHref = $self->getStat($sampleID);

    #transitions & transversion counter;
    $self->storeTrTv($targetHref, $refAllele, $geno);

    if(@$annotationsAref > 1) {next; } #for now we omit multiple transcript sites
    
    $aCount = $self->getAlleleCount($geno); #should be 2 for a diploid homozygote    
    if(!$aCount) {
      $self->tee_logger('warn', 'No allele count found for genotype $geno');
      next;
    }

    for my $annotationHref (@$annotationsAref) {
      $minorAllele = $annotationHref->minor_allele;
      # if it's an ins or del, there will be no deconvolutedGeno
      # taking this check out, because handling of del alleles does not work,
      # Annotate.pm sets the allele as the neegative length of the del, rather than D or E
      if(!$self->hasGeno($self->deconvoluteGeno($geno), $minorAllele) ) {
        next;
      }
      
      $annotationType = $annotationHref->annotation_type;

      if($self->debug) {
        say "we have the geno $geno";
        say "annotation type is $annotationType";
      } 
      #there is a more efficient option: just passing annotatypeType separately
      #I think this is cleaner (see use of shit in storeCount), and probably fast enough
      @featuresMerged = @{$featuresAref};
      push @featuresMerged, $annotationType;

      $self->storeCount(\@featuresMerged, $targetHref, $aCount);
    }
  }
  if($self->debug) {
    say "Stat record is";
    p $self->statsRecord;
  }
}

#topTargetHref remains the top level hash, always gets transitions/transversion record
#because we want genome-wide tr:tv
#insertions and deletions don't have transitions and transversions, so check for that
sub storeCount {
  my ($self, $featuresAref, $targetHref, $aCount) = @_;
  
  #to be more efficient we could track a feature index, and return when 
  #it == last featureAref index, and beyond that could store annotationType sep
  if(!@$featuresAref) { return };
  my $feature = shift @$featuresAref;
  if($self->debu) {
    say "in store count for feature $feature";
  }
  
  if($self->isBadFeature($feature) ) {return; }
  $targetHref = \%{$targetHref->{$feature} };
  $targetHref->{$self->statsKey}{$self->countKey} += $aCount;

  $self->storeCount($featuresAref, $targetHref, $aCount);
}

#transitions are unique, they are the only StatsCalculator created feature
# they should only be inserted in a single locaiton, else they'll be counted
# by sum(n*tr_i)
# by definition there can only be one tr or tv per site
sub storeTrTv {
  my ($self, $targetHref, $refAllele, $geno) = @_;
  my $trTvKey = $self->_getTr($refAllele, $geno);
  $targetHref->{$trTvKey}{$self->statsKey}{$self->countKey} += 1;
}

sub _getTr {
  my ($self, $refAllele, $geno) = @_;
  return $self->trTvKey(int(!!($self->isTr($geno) || $self->isTr($refAllele.$geno) ) ) );
}

# if it's a het; currently supports only diploid organisms
# 2nd if isn't strictly necessary, but safer, and allows this to be used
# as an alternative to isHet, isHomo
sub getAlleleCount {
  my ($self, $iupacAllele) = @_;
  if($self->isHomo($iupacAllele) ) {return 2;}
  if($self->isHet($iupacAllele) ) {return 1;}
  return undef;
}

no Moose::Role;
1;
