package Seq::Statistics::Percentiles::Store;

use Moose::Role;
use strict;
use warnings;

sub store
{
  my $self = shift;
  my $storageHashRef = shift;
  my @percentilesRef = sort{$a <=> $b} @{$self->percentilesRef}; #get ascending order of percentiles

  foreach my $ratioKey ( keys %{$self->ratioPercentilesRef} )
  {
    my @thisRatioPercentiles =  @{ $self->ratioPercentilesRef->{$ratioKey}->{$self->percentilesKey} }; #should be sorted ascending

    my $experimentRatioPercentilessRef = \%{ $storageHashRef->{$ratioKey}->{$self->percentilesKey} }; #auto-vivify

    %$experimentRatioPercentilessRef = map { $percentilesRef[$_] * 100 . 
      "th" => $thisRatioPercentiles[$_] } 0..$#thisRatioPercentiles;
  }
}

no Moose::Role;
1;