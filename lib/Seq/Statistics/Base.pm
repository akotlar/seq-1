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
    badGenos => 'first_index',
  },
  builder => '_buildDisallowedGeno',
);

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
    mapIUPAC => 'kv',
  }
);

#############################################################################
# Default value builder functions
#############################################################################
sub _buildDisallowedFeatures {
  return []
}

#only SNP IUPAC codes, I, D, and other Indel codes don't belong here
sub _buildIUPAC {
  return {A => 'A',C => 'C',G => 'G',T => 'T',R => 'AG',Y => 'CT', S => 'GC',
    W => 'AT', K => 'GT', M => 'AC', B => 'CGT', D => 'AGT', H => 'ACT',
    V => 'ACG', N => 'N'};  
}

sub _buildDisallowedGeno {
  return ['N'];
}

__PACKAGE__->meta->make_immutable;

1;
=head1 COPYRIGHT

Copyright (c) 2014 Alex Kotlar (<alex.kotlar@emory.edu>). All rights
reserved.

=head1 LICENSE