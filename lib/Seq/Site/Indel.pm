use 5.10.0;
use strict;
use warnings;

package Seq::Site::Indel;
# ABSTRACT: Class for seralizing indel sites
# VERSION

use Moose 2;
use Moose::Util::TypeConstraints;

use namespace::autoclean;

use Data::Dump qw/ dump /;

extends 'Seq::Site::Gene';
with 'Seq::Role::Serialize';

has minor_allele => (
  is       => 'ro',
  isa     => 'Maybe[Str]',
  required => 1,
);

has new_codon_seq => (
  is      => 'ro',
  isa     => 'Maybe[Str]',
  lazy    => 1,
  builder => '_set_new_codon_seq',
);

has new_aa_residue => (
  is      => 'ro',
  isa     => 'Maybe[Str]',
  lazy    => 1,
  builder => '_set_new_aa_residue',
);

has annotation_type => (
  is      => 'ro',
  isa     => 'Str',
  required => 1,
);

sub _set_new_codon_seq {
  my $self = shift;

  if ( $self->ref_codon_seq ) {
    return '-';
  }
  else {
    return;
  }
}

sub _set_new_aa_residue {
  my $self = shift;

  if ( $self->new_codon_seq ) {
    return '-';
  }
  else {
    return;
  }
}

__PACKAGE__->meta->make_immutable;

1;
