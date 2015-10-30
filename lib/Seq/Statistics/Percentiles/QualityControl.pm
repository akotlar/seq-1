package Seq::Statistics::Percentiles::QualityControl;

use Moose::Role;
use strict;
use warnings;

requires 'allRatios';
requires 'getPercVal';
requires 'target';
requires 'ratioName';

has qcFailKey => ( 
  is      => 'ro',
  isa     => 'Str',
  default => 'qcFail'
);

has failMessage => ( 
  is      => 'ro',
  isa     => 'Str',
  default => 'outside 95th percentile'
);

# any values that didn't have numerical values
has preScreened => (
  is => 'rw',
  isa => 'ArrayRef[Str|Num]',
  traits => ['Array'],
  handles => {
    blacklistID => 'push',
    blacklistedIDs => 'elements',
  }
);

#could also do this by checking ratioID position in ratios
#but wouldn't work for interpolated values
sub qc {
  my $self = shift; 

  my $failKey = $self->qcFailKey;
  my $mesage = $self->failMessage;
  my $ratioName = $self->ratioName;

  my $lower = $self->getPercVal(0);
  my $upper = $self->getPercVal(2);
  
  my ($id, $val);
  for my $ratio ($self->allRatios) {
    $id = $ratio->[0];
    $val = $ratio->[1];

    if($val < $lower || $val > $upper) {
      push @{$self->target->{$failKey}{$id} }, "$ratioName $mesage";
    }
  }
  
  for my $id ($self->blacklistedIDs) {
    push @{$self->target->{$failKey}{$id} }, "$ratioName $mesage";
  }
}

no Moose::Role;
1;
