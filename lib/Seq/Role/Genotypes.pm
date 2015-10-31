package Seq::Role::Genotypes;
use strict;
use warnings;
use Moose::Role;
use namespace::autoclean
# the genotype codes below are based on the IUPAC ambiguity codes with the notable
#   exception of the indel codes that are specified in the snpfile specifications

has iupac => (
  is => 'ro',
  isa => 'HashRef',
  traits => ['Hash'],
  handles => {
    validGeno => 'exists',
    deconvoluteGeno => 'get',
    getGeno => 'get', #fallback, in case semantic interpretation different
  },
  init_arg => undef,
  buidler => '_buildIUPAC',
);

#IUPAC also includes D => 'AGT', H => 'ACT', # may want to think about renaming D,H
#also includes V => 'ACG', B => 'CGT', do we want to include these?
sub _buildIUPAC {
  return {A => 'A',C => 'C',G => 'G',T => 'T',R => 'AG',Y => 'CT',S => 'GC',
    W => 'AT', K => 'GT', M => 'AC', D => '-', I => '+', E => '-*', H => '+*'};  
}

#can also do this with ArrayRef and first_index, not sure which is faster
has hetGenos => (
  is => 'ro',
  isa => 'HashRef',
  traits => ['Hash'],
  handles => {
    isHet => 'get'
  },
  default => sub { {
    K => 1,
    M => 1,
    R => 1,
    S => 1,
    W => 1,
    Y => 1,
    E => 1,
    H => 1,
  } }
);

has homGenos => (
  is => 'ro',
  isa => 'HashRef',
  traits => ['Hash'],
  handles => {
    isHomo => 'get',
  },
  default => sub { {
    A => 1,
    C => 1,
    G => 1,
    T => 1,
    D => 1,
    I => 1,
  } }
);
#an alternative way to look for homozygote vs heterozygote:
# sub deconvAlleleCount {
#   my ($self, $geno) = @_;
#   if(length($self->getGeno($geno) ) == 1) { return 2; }
#   return 1;
# }

#@param {Str} $geno1;
#@param {Str} $geno2;
sub hasGeno {
  my ($self, $geno1, $geno2) = @_;
  if($geno1 eq $geno2) {return 1; } #both are IUPAC codes
  if(index($geno1, $geno2) > -1 ) {return 1; } #geno1 is iupac
  if(index($geno2, $geno1) > -1 ) {return 1; } #geno2 is iupac or het
  #in the case of E, and later maybe H, we may have -{Num} or +{Num}
  #leaving more flexible in case we later do {Num}- or {Num}+, say for neg strand
  #this could be abused however
  if(index($geno1, '-') > -1 && index($geno2, '-') > -1) {return 1; }
  if(index($geno1, '+') > -1 && index($geno2, '+') > -1) {return 1; }
}

no Moose::Role;
1;