package Seq::Statistics::Ratios::Store;

use Moose::Role;
use strict;
use warnings;

sub _storeRatioKeysInHash #for easy retrieval / visualization in downstream scripts, primarily my webapp
{
  my $self = shift;
  my $storageHashRef = shift;
  my @siteRatioKeys = ();
  
  my $trTvRatioKey = $self->_getTransitionTransversionKeys(); #gets last item of returned array of transition,transversion keys

  foreach my $siteKey ( keys %{$self->siteTypeRatiosOrganizerRef} )
  {
    my $ratioKey = $self->_getSiteDenominatorRatioKeys($siteKey); 
    push @siteRatioKeys, $ratioKey;
  }
  push @siteRatioKeys, $trTvRatioKey;

  $storageHashRef->{$self->allRatiosKey} = \@siteRatioKeys;
}

no Moose::Role;
1;