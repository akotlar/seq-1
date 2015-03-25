use 5.10.0;
use strict;
use warnings;

package Seq::Site::Annotation;
# ABSTRACT: Class for seralizing annotation sites
# VERSION

use Moose 2;
use Moose::Util::TypeConstraints;

use namespace::autoclean;

extends extends 'Seq::Site', 'Seq::Site::Gene', 'Seq::Site::Snp';
with 'Seq::Role::Serialize';

enum non_missing_base_types => [ qw( A C G T ) ];

has minor_allele => (
  is => 'ro',
  isa => 'non_missing_base_types',
  required => 1,
);

has new_codon_seq => (
  is => 'ro',
  isa => 'Maybe[Str]',
  lazy => 1,
  builder => '_set_new_codon_seq',
);

has new_aa_residue => (
  is => 'ro',
  isa => 'Maybe[Str]',
  lazy => 1,
  builder => '_set_new_aa_residue' ,
);

has annotation_type => (
  is => 'ro',
  isa => 'Str',
  lazy => 1,
  builder => '_set_annotation_type' ,
);

sub _set_new_codon_seq {
  my $self = shift;
  my $new_codon = $self->ref_codon_seq;
  if ($new_codon) {
    substr( $new_codon, ( $self->codon_position - 1 ), 1, $self->minor_allele );
    return $new_codon;
  }
  else {
    return;
  }
}

sub _set_new_aa_residue {
  my $self = shift;
  # if ($self->new_codon_seq) {
  #   return $self->codon_2_aa( $self->new_codon_seq );
  # }
  # else {
  #   return;
  # }
  return $self->codon_2_aa( $self->new_codon_seq );
}

sub _set_annotation_type {
  my $self = shift;
  if ($self->new_aa_residue) {
      if ($self->new_aa_residue eq $self->ref_aa_residue) {
        return 'Silent';
      }
      else {
        return 'Replacement';
      }
  }
  else {
    return 'Non-Coding';
  }
}

override seralizable_attributes => sub {
  return qw( abs_pos ref_base transcript_id site_type strand ref_codon_seq
  codon_number codon_position ref_aa_residue error_code alt_names
  genotype new_codon_seq new_aa_residue annotation_type
  snp_id feature );
};

__PACKAGE__->meta->make_immutable;

1;
