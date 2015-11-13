use 5.10.0;
use strict;
use warnings;

package Seq::Site::Indel;

our $VERSION = '0.001';

# ABSTRACT: Class for seralizing indel sites
# VERSION

use Moose 2;
use namespace::autoclean;
use Moose::Util::TypeConstraints;
use DDP;

use Seq::Site::Indel::Type;

extends 'Seq::Site::Gene';
with 'Seq::Role::Serialize';

has minor_allele => (
  is => 'ro',
  isa => 'Str',
  required => 1,
);

has annotation_type => (
  is => 'ro',
  isa => 'Str',
  required => 1,
);

# #these won't work for now, probably handle in Indel/Definition
# has new_codon_seq => (
#   is      => 'ro',
#   isa     => 'Maybe[Str]',
#   lazy    => 1,
#   builder => '_set_new_codon_seq',
# );

# has new_aa_residue => (
#   is      => 'ro',
#   isa     => 'Maybe[Str]',
#   lazy    => 1,
#   builder => '_set_new_aa_residue',
# );
# #Here, for a deletion, it would be confusing to show a longer allele
# #ned to think about how to represent that 
# sub _set_new_codon_seq {
#   my $self = shift;

#   if ( $self->ref_codon_seq ) {
#     return $self->indType . $self->indLength;
#   }
#   else {
#     return;
#   }
# }

# sub _set_new_aa_residue {
#   my $self = shift;

#   if ( $self->new_codon_seq ) {
#     return $self->indType . $self->indLength;
#   }
#   else {
#     return;
#   }
# }

__PACKAGE__->meta->make_immutable;

1;
