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
use namespace::autoclean; #remove moose keywords after compilation

#############################################################################
# Non required vars passable to constructor during new
# All can be passed either by new( {varName1:value,...} ) or new( {configfile=>'path/to/yamlfile.yaml'} )
#############################################################################
has statsRecord => (
  is      => 'rw',
  isa     => 'HashRef',
  traits  => ['Hash'],
  handles => {
    getStat     => 'get',
    setStat     => 'set',
    hasStat     => 'exists',
    statsKv     => 'kv',
    statSamples => 'keys',
    hasStats    => 'keys',
  },
  init_arg => undef,
  default  => sub { return {} },
);

has disallowedFeatures => (
  is      => 'ro',
  traits  => ['Hash'],
  isa     => 'HashRef[Str]',
  handles => { isBadFeature => 'exists', },
  default => sub { return { 'NA' => 1 } },
);

# This is VERY slow; 41220 calls takes 1.25s on hgcc
# around 'isBadFeature' => sub {
#   my ($orig, $self, $value) = @_;
#   return $self->$orig( sub { $_ eq $value } ) > -1;
# };

# has stuff => (
#   is => 'ro',
#   does => 'Seq::Role::Genotypes',
#   handles => [qw(validGeno deconvoluteGeno getGeno isHet isHomo hasGeno)]
# );

#############################################################################
# Default value builder functions
#############################################################################

#############Public##############

__PACKAGE__->meta->make_immutable;

1;

=head1 COPYRIGHT

Copyright (c) 2014 Alex Kotlar (<alex.kotlar@emory.edu>). All rights
reserved.

=head1 LICENSE
