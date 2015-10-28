#not currently in use; stores expected values;
package Seq::Statistics::Expected;

use 5.10.0;
use strict;
use warnings;

use Moose::Role;
use Moose::Util::TypeConstraints;
use namespace::autoclean;#remove moose keywords after compilation

use YAML::XS;
use File::Basename; 
#############################################################################
# Subtypes
#############################################################################
subtype 'ExperimentType',
as 'Str',  
where { $_ eq 'exome' || $_ eq 'genome' };

#if the user supplies an experiment type, we can include expected ratio values in the experiment statistics summary
has expectedValuesRef =>
( is      => 'rw',
  traits  => ['Hash'],
  isa     => 'Maybe[HashRef]', #hashref or undefined
  handles => {
    setExpected => 'set',
  },
  lazy => '1',
  builder => '_buildExpectedValuesRef'
);

has experimentType => 
(
  is  => 'ro',
  isa => 'Maybe[ExperimentType]', #ExperimentType or undef
  default => 'genome',
  predicate => 'has_experimentType'
);

has expectedKey =>
( is      => 'ro',
  isa     => 'Str',
  default => 'expected',
  init_arg => undef 
);

sub _buildExpectedValuesRef
{
  my $self = shift;

  if( !$self->has_assembly || !$self->has_experimentType)
  {
    return undef;
  }
  
  try #config file may not have the expected values, just tell the user
  {
    say dirname(__FILE__).'/config/StatisticsCalculator/expectedValues.yml';
    my $config = YAML::XS::LoadFile( dirname(__FILE__).'/config/StatisticsCalculator/expectedValues.yml' );

    if( exists( $config->{$self->assembly} ) && exists( $config->{$self->assembly}->{$self->experimentType} ) ) #prevent autovivify
    {
      print "Expected Values:\n" if $self->verbose; print Dumper( $config->{$self->assembly}->{$self->experimentType} ) if $self->verbose;
      
      return $config->{$self->assembly}->{$self->experimentType};
    }
  }
  catch
  {
    cluck $_; #don't die, we may not have any expected values
    return undef;
  }
}

sub _storeExpectedValuesInHash
{
  my $self = shift;
  
  $self->setExpected($self->expectedKey, $self->expectedValuesRef);
}

no Moose::Role;
1;