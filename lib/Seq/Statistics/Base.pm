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

use Modern::Perl '2013';
use Moose;
  with 'MooseX::SimpleConfig'; #all constructor arguments can be overriden by passing the constructor (during "new") : {configfile=>'path/to/yamlfile.yaml'} with appropriate key:value pairs 
  with 'MooseX::Getopt'; #allows passing command line args, including -configfile, when used with StatisticsCalculator->new_with_optinos()
use Moose::Util::TypeConstraints;
use namespace::autoclean;#remove moose keywords after compilation
use YAML::XS;
use Try::Tiny;
use Data::Dumper;
use Hash::Merge;
use POSIX;
use Carp qw(cluck confess);
use Cwd;
use File::Basename;   

my $rq = eval #optional modules
{
  require threads;
  threads->import();

  require threads::shared;
  threads::shared->import();
  1;
};

#############################################################################
# Subtypes
#############################################################################
subtype 'ExperimentType',
as 'Str',  
where { $_ eq 'exome' || $_ eq 'genome' };

#############################################################################
# Non required vars passable to constructor during new 
# All can be passed either by new( {varName1:value,...} ) or new( {configfile=>'path/to/yamlfile.yaml'} ) 
#############################################################################
has assembly => 
(
  is  => 'ro',
  isa => 'Str',
  predicate => 'has_assembly'
);

has allowedCodesRef =>
( is      => 'ro',
  isa     => 'HashRef[Int]',
  builder => '_buildAllowedCodesRef'
);

has disallowedTypesRef =>
( is      => 'ro',
  traits  => 'Hash',
  isa     => 'HashRef[Int]',
  builder => '_buildDisallowedTypesRef',
  handles => {
    disallowed => 'get',
  }
);

has confidenceIntervalfailMessage =>
( is      => 'ro',
  isa     => 'Str',
  default => 'outside 2 standard deviations'
);

has verbose =>
( is      => 'ro',
  isa     => 'Int',
  default => '0'
);

has experimentType => 
(
  is  => 'ro',
  isa => 'Maybe[ExperimentType]', #ExperimentType or undef
  default => 'genome',
  predicate => 'has_experimentType'
);





#############################################################################
# Vars not passable to constructor (private vars)
#############################################################################


has iupac =>
(
  is  => 'rw',
  isa => 'HashRef[Str]',
  traits => ['Hash'],
  lazy => '1',
  builder => 'buildIUPAC',
  init_arg => undef,
  handles => {
    convertGeno => 'get',
  }
);




has statisticsKey =>
( is      => 'ro',
  isa     => 'Str',
  default => 'statistics',
  init_arg => undef 
);

has qcFailKey =>
( is      => 'ro',
  isa     => 'Str',
  default => 'qcFail',
  init_arg => undef 
);





#we store the ratio keys (like Transition:Transversion) in the top level statistic for the experiment in allRatiosKey : [key1,key2,key3, etc]
has allRatiosKey =>
( is      => 'ro',
  isa     => 'Str',
  default => 'ratioKeys',
  init_arg => undef 
);

#keeper of our statistics; can be many hashrefs deep
has statisticRecordRef => 
(
  is  => 'rw',
  isa => "HashRef",
  default => sub{ {} },
  init_arg => undef 
);

has countKey => 
(
  is => 'rw',
  isa => 'Str',
  lazy => '1',
  default => 'count',
)

has allowedTypesRef =>
( is      => 'ro',
  isa     => 'HashRef[Int]',
  builder => '_buildAllowedTypesRef'
);

sub _buildAllowedTypesRef #this should live in yml
{
  return {SNP => 1,MULTIALLELIC => 1};
}

#############################################################################
# Default value builder functions
#############################################################################

sub _buildIUPAC #this should live in yml
{
  return {A => "A",C => "C",G => "G",T => "T",R => "AG",Y => "CT", S => 'GC'.
    W => 'AT', K => 'GT', M => 'AC', B => 'CGT', D => 'AGT', H => 'ACT',
    V => 'ACG'}; #R is IUPAC AG, Y is IUPAC CT
}



sub _buildAllowedCodesRef
{
  return {Silent => 1,Replacement => 1}
}



sub _buildDisallowedTypesRef
{
  return {N=>1};
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

sub _getValue
{
  my $self = shift;
  my($key,$hashReference,$subKey) = @_;

  if($subKey)
  {
    return $hashReference->{$key}->{$subKey};
  }
  else
  {
    return $hashReference->{$key};
  }
}

__PACKAGE__->meta->make_immutable;

1;
=head1 COPYRIGHT

Copyright (c) 2014 Alex Kotlar (<alex.kotlar@emory.edu>). All rights
reserved.

=head1 LICENSE