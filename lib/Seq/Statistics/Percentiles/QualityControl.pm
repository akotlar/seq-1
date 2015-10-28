package Percentiles::QualityControl;

use Moose::Role;
use strict;
use warnings;

requires 'percentiles';
requires 'qcFailKey';
requires 'ratioName';

has ciMessage =>
( 
  is      => 'ro',
  isa     => 'Str',
  default => 'outside 95th percentile'
);

sub qc
{
  my ($self, $keysAref, $valuesAref, $destHref) = @_;

  my $qcFailKey = $self->qcFailKey;
  my $ciMessage = $self->ciMessage;
  my $ratioName = $self->ratioName;

  my $lower = $self->getPercentile(0);
  my $upper = $self->getPercentile(2);
  
  my $index = 0;
  for my $ratio (@$valuesAref)
  {
    if($ratio < $lower || $ratio > $upper)
    {
      $destHref->{$qcFailKey}{$keysAref->[$index] } = "$ratioName $ciMessage";
    }
    $index++;
  }
}

1;
