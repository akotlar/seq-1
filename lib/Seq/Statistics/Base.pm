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

package Seq::Statistics::Base;

use 5.10.0;
use Moose;
use namespace::autoclean;#remove moose keywords after compilation

#############################################################################
# Non required vars passable to constructor during new 
# All can be passed either by new( {varName1:value,...} ) or new( {configfile=>'path/to/yamlfile.yaml'} ) 
#############################################################################
has statsRecord => (
  is => 'rw',
  isa => 'HashRef',
  traits => ['Hash'],
  handles => {
    getStat => 'get',
    setStat => 'set',
    hasStat => 'exists',
    statsKv => 'kv',
    statSamples => 'keys',
  },
  init_arg => undef,
  default => sub { return {} },
);

has disallowedGeno => (
  is      => 'ro',
  traits  => ['Array'],
  isa     => 'ArrayRef[Str]',
  handles => {
    isBadGeno => 'first_index',
  },
  builder => '_buildDisallowedGeno',
);

around 'isBadGeno' => sub {
  my ($orig, $self, $value) = @_;
  return $self->$orig( sub { $_ eq $value } ) > -1;
};

has disallowedFeatures => (
  is      => 'ro',
  traits  => ['Array'],
  isa     => 'ArrayRef[Str]',
  handles => {
    isBadFeature => 'first_index',
  },
  builder => '_buildDisallowedFeatures',
);

around 'isBadFeature' => sub {
  my ($orig, $self, $value) = @_;
  return $self->$orig( sub { $_ eq $value } ) > -1;
};

#############################################################################
# Vars not passable to constructor (private vars)
#############################################################################
has iupac => (
  is  => 'rw',
  isa => 'HashRef[Str]',
  traits => ['Hash'],
  builder => '_buildIUPAC',
  init_arg => undef,
  handles => {
    deconvoluteIUPAC => 'get',
  }
);

#############################################################################
# Default value builder functions
#############################################################################
sub _buildDisallowedFeatures {
  return ['NA'];
}

#SNP, Indel codes; only SNP are true IUPAC.
#differences from rest of Seq codes: het indels are given a * as 2nd character
#this is so that we can check whether it's a het or not without relying on a
#separate hash
sub _buildIUPAC {
  return {A => 'A',C => 'C',G => 'G',T => 'T',R => 'AG',Y => 'CT', S => 'GC',
    W => 'AT', K => 'GT', M => 'AC', B => 'CGT', D => 'AGT', H => 'ACT',
    V => 'ACG', D => '-', I => '+', E => '-*', H => '+*'};  
}

sub _buildDisallowedGeno {
  return ['N'];
}

#############Public##############
# if it's a het; currently supports only diploid organisms
sub deconvAlleleCount {
  my ($self, $deconvolutedAllele) = @_;
  if(length($deconvolutedAllele) == 1) { return 2; }
  return 1;
}

# sub hasGeno {
#   my ($self, $geno1, $geno2) = @_;
  
# }

__PACKAGE__->meta->make_immutable;

1;
=head1 COPYRIGHT

Copyright (c) 2014 Alex Kotlar (<alex.kotlar@emory.edu>). All rights
reserved.

=head1 LICENSE