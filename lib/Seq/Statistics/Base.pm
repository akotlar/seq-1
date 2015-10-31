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

with 'Seq::Role::Genotypes';

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

#############Public##############
# if it's a het; currently supports only diploid organisms
# 2nd if isn't strictly necessary, but safer, and allows this to be used
# as an alternative to isHet, isHomo
sub getAlleleCount {
  my ($self, $iupacAllele) = @_;
  if($self->isHomo($iupacAllele) ) {return 2;}
  if($self->isHet($iupacAllele) ) {return 1;}
  return undef;
}

__PACKAGE__->meta->make_immutable;

1;
=head1 COPYRIGHT

Copyright (c) 2014 Alex Kotlar (<alex.kotlar@emory.edu>). All rights
reserved.

=head1 LICENSE