use 5.10.0;
use strict;
use warnings;

package Seq::Annotate::Snp;

our $VERSION = '0.001';

# ABSTRACT: Base class for seralizing annotated variant sites
# VERSION

=head1 DESCRIPTION

  @class B<Seq::Annotate::Snp>
  #TODO: Check description

  @example

Used in: Seq::Annotate

=cut

use Moose 2;
use Moose::Util::TypeConstraints;

use Carp qw/ confess /;
use namespace::autoclean;

use Seq::Site::Snp;
use Seq::Site::Annotation;

use Data::Dump qw/ dump /;

with 'Seq::Role::Serialize';

enum SnpType     => [ 'SNP',    'MULTIALLELIC', 'REF', ];
enum GenomicType => [ 'Exonic', 'Intronic',     'Intergenic' ];
#enum AnnotationType  =>
#  [ '5UTR', 'Coding', '3UTR', 'non-coding RNA', 'Splice Donor', 'Splice Acceptor' ];

has abs_pos      => ( is => 'ro', isa => 'Int',          required => 1, );
has allele_count => ( is => 'ro', isa => 'Str',          required => 1, );
has alleles      => ( is => 'ro', isa => 'Str',          required => 1, );
has chr          => ( is => 'ro', isa => 'Str',          required => 1, );
has genomic_type => ( is => 'ro', isa => 'GenomicType',  required => 1, );
has het_ids      => ( is => 'ro', isa => 'Str',          default  => '', );
has hom_ids      => ( is => 'ro', isa => 'Str',          default  => '', );
has pos          => ( is => 'ro', isa => 'Int',          required => 1, );
has ref_base     => ( is => 'ro', isa => 'Str',          required => 1, );
has scores       => ( is => 'ro', isa => 'HashRef[Str]', default  => sub { {} }, );
has var_allele   => ( is => 'ro', isa => 'Str',          required => 1, );
has var_type     => ( is => 'ro', isa => 'SnpType',      required => 1, );
has warning      => ( is => 'ro', isa => 'Str',          default  => 'NA', );

has gene_data => (
  is       => 'ro',
  isa      => 'ArrayRef[Maybe[Seq::Site::Annotation]]',
  required => 1,
);

has snp_data => (
  is       => 'ro',
  isa      => 'ArrayRef[Maybe[Seq::Site::Snp]]',
  required => 1,
);

# these are the attributes to export
my @attrs =
  qw/ chr pos allele_count alleles var_type ref_base genomic_type het_ids hom_ids warning /;

sub as_href {
  my $self = shift;

  my %hash;

  for my $attr (@attrs) {
    $hash{$attr} = $self->$attr;
  }

  my $scores_href = $self->scores;

  for my $score ( sort keys %$scores_href ) {
    $hash{$score} = $scores_href->{$score};
  }

  my $gene_site_href = {};
  for my $gene ( @{ $self->gene_data } ) {
    $gene_site_href = $self->_join_href( $gene_site_href, $gene->as_href_with_NAs );
  }

  my $snp_site_href = {};
  for my $snp ( @{ $self->snp_data } ) {
    $snp_site_href = $self->_join_href( $snp_site_href, $snp->as_href_with_NAs );
  }

  return { %hash, %$gene_site_href, %$snp_site_href };
}

# _join_href joins two hash references and any underlying hashes recursively.
# It is assumed that if there's a value in one key that is a hash reference
# then the other hashRef also has a hash reference for that key.
sub _join_href {
  my ( $self, $old_href, $new_href ) = @_;

  my %attrs = map { $_ => 1 } ( keys %$old_href, keys %$new_href );
  my %merge;

  for my $attr ( keys %attrs ) {
    my $old_val = $old_href->{$attr};
    my $new_val = $new_href->{$attr};
    if ( defined $old_val and defined $new_val ) {
      # assuming if one is a hashref then they both are.
      if ( ref $old_val eq 'HASH' ) {
        $merge{$attr} = $self->_join_href( $old_val, $new_val );
      }
      elsif ( $old_val eq $new_val ) {
        $merge{$attr} = join ";", $old_val, $new_val;
      }
      else {
        my @old_vals = split /\;/, $old_val;
        push @old_vals, $new_val;
        $merge{$attr} = join ";", @old_vals;
      }
    }
    elsif ( defined $old_val ) {
      $merge{$attr} = $old_val;
    }
    elsif ( defined $new_val ) {
      $merge{$attr} = $new_val;
    }
  }
  return \%merge;
}

__PACKAGE__->meta->make_immutable;

1;
