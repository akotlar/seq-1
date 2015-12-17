package Seq::Role::Progress;

use Moose;
use strict;
use warnings;
use 5.10.0;
use namespace::autoclean;

has progressCounter => (
  is      => 'rw',
  traits  => ['Counter'],
  isa     => 'Num',
  default => 0,
  handles => {
    incProgressCounter   => 'inc',
    resetProgressCounter => 'reset',
  },
  writer => 'setProgressCounter',
  lazy => 1,
);

before incProgressCounter => sub {
  my $self = shift;

  if($self->progressCounter == $self->progressBatch) {
    $self->callProgressAction();
    $self->setProgressCounter(1);
  }
};

has progressBatch => (
  is => 'ro',
  isa => 'Int',
  default => 1000,
  lazy => 1,
);

has progress => (
  is => 'rw',
  isa => 'Num',
  traits => ['Number'],
  handles => {
    recordProgress => 'add',
  },
  default => 0,
  lazy => 1,
);

has fileLines => (
  is => 'ro',
  isa => 'Num',
  writer => 'setTotalLinesInFile',
  lazy => 1,
  default => 0,
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
  lazy => 1,
);


sub progressFraction {
  my $self = shift;

  return $self->progress / $self->fileLines unless !$self->fileLines;
  return;
};

__PACKAGE__->meta->make_immutable;
1;