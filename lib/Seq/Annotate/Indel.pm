use 5.10.0;
use strict;
use warnings;

package Seq::Annotate::Indel;

our $VERSION = '0.001';

# ABSTRACT: Base class for seralizing genomic indels.
# VERSION

=head1 DESCRIPTION

  @class B<Seq::Annotate::Indel>
  #TODO: Check description

  @example

Used in: Seq::Annotate

=cut

use Moose 2;
use Moose::Util::TypeConstraints;

use Seq::Site::Indel;

extends 'Seq::Annotate::Site';
with 'Seq::Role::Serialize';

enum IndelType => [ 'DEL', 'INS' ];

has alleles      => ( is => 'ro', isa => 'Str',       required => 1, );
has allele_count => ( is => 'ro', isa => 'Str',       required => 1, );
has het_ids      => ( is => 'ro', isa => 'Str',       default  => 'NA', lazy => 1 );
has hom_ids      => ( is => 'ro', isa => 'Str',       default  => 'NA', lazy => 1 );
has var_allele   => ( is => 'ro', isa => 'Str',       required => 1, );
has var_type     => ( is => 'ro', isa => 'IndelType', required => 1, );

# the objects stored in gene_data really only need to do as_href_with_NAs(),
# which is a method in Seq::Role::Seralize
has '+gene_data' => (
  is       => 'ro',
  isa      => 'ArrayRef[Maybe[Seq::Site::Indel]]',
  required => 1,
);

# these are the attributes to export
override attrs => sub {
  state $attrs = [
    'chr',          'pos',     'allele_count', 'alleles', 'var_type', 'ref_base',
    'genomic_type', 'het_ids', 'hom_ids',      'warning'
  ];
  return $attrs;
};

__PACKAGE__->meta->make_immutable;

1;
