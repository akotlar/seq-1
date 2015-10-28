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

package Seq::StatisticsBase;

use Moose;
  with 'MooseX::SimpleConfig'; #all constructor arguments can be overriden by passing the constructor (during "new") : {configfile=>'path/to/yamlfile.yaml'} with appropriate key:value pairs 
  with 'MooseX::Getopt'; #allows passing command line args, including -configfile, when used with StatisticsCalculator->new_with_optinos()

use namespace::autoclean;#remove moose keywords after compilation

#############################################################################
# Non required vars passable to constructor during new 
# All can be passed either by new( {varName1:value,...} ) or new( {configfile=>'path/to/yamlfile.yaml'} ) 
#############################################################################
# has assembly => 
# (
#   is  => 'ro',
#   isa => 'Str',
#   predicate => 'has_assembly'
# );
has statsRecord => (
  is => 'rw',
  isa => 'HashRef',
  traits => ['Hash'],
  handles => {
    getStat => 'get',
    setStat => 'set',
    statsKv => 'kv',
    statSamples => 'keys',
  },
  init_arg => undef,
  default => sub { return {} },
);

has disallowedGeno =>
( is      => 'ro',
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
has iupac =>
(
  is  => 'rw',
  isa => 'HashRef[Str]',
  traits => ['Hash'],
  builder => 'buildIUPAC',
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

sub _buildIUPAC #this should live in yml
{
  return {A => "A",C => "C",G => "G",T => "T",R => "AG",Y => "CT", S => 'GC'.
    W => 'AT', K => 'GT', M => 'AC', B => 'CGT', D => 'AGT', H => 'ACT',
    V => 'ACG', N => 'N'}; #R is IUPAC AG, Y is IUPAC CT
}

sub _buildDisallowedGeno
{
  return ['N'];
}

#############################################################################
# Private Methods
#############################################################################
sub _makeUnique
{
  my $self = shift;
  my $recordReferenceOrPrimitive = shift;

  if(ref($recordReferenceOrPrimitive) eq 'ARRAY')
  {
    my %unique;

    for my $key (keys @$recordReferenceOrPrimitive)
    {
      $unique{$key} = 1;
    }
    return join(";",keys %unique);
  }
  elsif(ref($recordReferenceOrPrimitive) eq 'HASH')
  {
    confess "Record passed to Snpfile::StatisticsCalculator::makeUnique was hash, unsupported";
  } 
  return $recordReferenceOrPrimitive;
}

__PACKAGE__->meta->make_immutable;

1;
=head1 COPYRIGHT

Copyright (c) 2014 Alex Kotlar (<alex.kotlar@emory.edu>). All rights
reserved.

=head1 LICENSE