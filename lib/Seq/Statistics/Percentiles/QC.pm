package Seq::Statistics::Percentiles::QC;

use Moose::Role;
use strict;
use warnings;

sub store
{
  my $self = shift;
  my $masterHashReference = shift;

  foreach my $ratioKey ( keys %{$self->ratioPercentilesRef} )
  { 
    my $thisRatioPercentilesRef = $self->ratioPercentilesRef->{$ratioKey}->{$self->percentilesKey};
    my $lowerPercentileValue = $thisRatioPercentilesRef->[0];
    my $upperPercentileValue = $thisRatioPercentilesRef->[-1];

    if(!defined($lowerPercentileValue) || !defined($upperPercentileValue) || scalar @$thisRatioPercentilesRef <= 1) #undefined value or length of array is 1
    {
      cluck "Improper ratioPercentilesRef found in StatisticsCalculator.pm";
      next;
    }
    ##for each sample record whether or not sample is within acceptable range
    foreach my $sampleID (keys %$masterHashReference)
    {
      if(!exists($self->statisticRecordRef->{$sampleID}))
      {
        cluck "Sample ID $sampleID not found in _qcOnPercentiles, StatisticsCalculator.pm";
        next;
      }
      my $sampleRatioValue = $self->statisticRecordRef->{$sampleID}->{$self->statisticsKey}->{$ratioKey};

      if( defined($sampleRatioValue) && ( $sampleRatioValue > $upperPercentileValue || $sampleRatioValue < $lowerPercentileValue) )
      {
        # not within confidence interval; failed QC
        $self->statisticRecordRef->{$sampleID}->{$self->statisticsKey}->{$self->qcFailKey}->{$ratioKey} = $self->confidenceIntervalfailMessage;

        $self->statisticRecordRef->{$self->statisticsKey}->{$self->qcFailKey}->{$sampleID}->{$ratioKey} = $self->confidenceIntervalfailMessage;  
      }
    }
  }
}

no Moose::Role;
1;