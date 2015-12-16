package Seq::Role::Progress;

use Moose::Role;
use strict;
use warnings;
use 5.10.0;

has progressCounter => (
  is      => 'rw',
  traits  => ['Counter'],
  isa     => 'Num',
  default => 0,
  handles => {
    incProgressCounter   => 'inc',
    resetProgressCounter => 'reset',
  },
);

before incProgressCounter => sub {
  my $self = shift;

  if($self->progressCounter >= $self->progressBatch) {
    $self->recordProgress($self->progressCounter);
    $self->callProgressAction($self->progress);
    $self->resetProgressCounter;
  }
};

has progressBatch => (
  is => 'ro',
  isa => 'Int',
  default => 1000,
);

has progress => (
  is => 'rw',
  isa => 'Num',
  traits => ['Number'],
  handles => {
    recordProgress => 'add',
  }
);

around recordProgress => sub {
  my $orig = shift;
  my $self = shift;

  $self->$orig($_[0] / $self->fileLines);
};

has fileLines => (
  is => 'ro',
  isa => 'Num',
  writer => 'setTotalLinesInFile',
);

#theoretically we can make this an array of coderefs
#however, not sure how slow this is, so for now, only allow one action
has progressAction => (
  is => 'rw',
  isa => 'CodeRef',
  default => sub{ sub{} },
  traits => ['Code'],
  handles => {
    callProgressAction => 'execute',
  },
  writer => 'setProgressAction',
);


no Moose::Role;
1;