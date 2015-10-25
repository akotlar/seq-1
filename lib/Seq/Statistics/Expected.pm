package Seq::Statistics::Expected;

use Moose::Role;
use strict;
use warnings;

#if the user supplies an experiment type, we can include expected ratio values in the experiment statistics summary
has expectedValuesRef =>
( is      => 'rw',
  isa     => 'Maybe[HashRef]', #hashref or undefined
  lazy => '1',
  builder => '_buildExpectedValuesRef'
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
  my $storageHashRef = shift;

  if( defined($self->expectedValuesRef) )
  {
    $storageHashRef->{$self->expectedKey} = $self->expectedValuesRef;
  }
}

use Moose::Role;
use 1;