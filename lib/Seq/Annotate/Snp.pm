use 5.10.0;
use strict;
use warnings;

package Seq::Annotate::Snp;
# ABSTRACT: Base class for seralizing annotated snps.
# VERSION

=head1 DESCRIPTION

  @class B<Seq::Indel>
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

has abs_pos => ( is => 'ro', isa => 'Int', required => 1,);
has chr => ( is => 'ro', isa => 'Str', required => 1,);
has pos => ( is => 'ro', isa => 'Int', required => 1, );
has site_type => ( is => 'ro', isa => 'Str', required => 1,);
has ref_base => ( is => 'ro', isa => 'Str', required => 1,);
has min_allele => ( is => 'ro', isa => 'Str', required => 1,);
has genomic_annotation_code => ( is => 'ro', isa => 'Str', required => 1,);
has scores => ( is => 'ro', isa => 'HashRef[Str]', required => 1,);

has gene_sites => (
  is => 'ro',
  isa => 'ArrayRef[Maybe[Seq::Site::Annotation]]',
  required => 1,
);

has snp_sites => (
  is => 'ro',
  isa => 'ArrayRef[Maybe[Seq::Site::Snp]]',
  required => 1,
);

#
#  this method joins together data; preserving the sequential order
#
sub _join_href {
  my ( $self, $old_href, $new_href ) = @_;

  my %attrs = map { $_ => 1 } ( keys %$old_href, keys %$new_href );
  my %merge;

  for my $attr ( keys %attrs ) {
    my $old_val = $old_href->{$attr};
    my $new_val = $new_href->{$attr};
    if ( defined $old_val and defined $new_val ) {
      if ( $old_val eq $new_val ) {
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


#sub BUILDARGS {
#  my $class = shift;
#  my $href = $_[0];
#
#  if ( scalar @_ > 1 || reftype($href) ne 'HASH') {
#    confess "Error: $class expects hash reference\n"; #  }
#  else {
#    my %hash;
#
#    my (@gene_objs, @snp_objs);
#
#    if (exists $href->{gene_data}) {
#      for my $gene_href ( @{ $href->{gene_data} } ){
#        my $gene_obj = Seq::Site::Annotation->new( $gene_href );
#        push @gene_objs, $gene_obj;
#      }
#      $hash{gene_sites} = \@gene_objs;
#    }
#    else {
#      $hash{gene_sites} = [];
#    }
#    
#    if (exists $href->{snp_data}) {
#      for my $snp_href ( @{ $href->{snp_data} }) {
#        my $snp_obj = Seq::Site::Snp->new( $snp_href );
#        push @snp_objs, $snp_obj;
#      }
#      $hash{snp_sites} = \@snp_objs;
#    }
#    else {
#      $hash{snp_sites} = [];
#    }
#
#    for my $attr (keys %$href) {
#      next if $attr eq 'snp_data' || $attr eq 'gene_data';
#      $hash{$attr} = $href->{$attr};
#    }
#    return $class->SUPER::BUILDARGS( \%hash );
#  }
#}

__PACKAGE__->meta->make_immutable;

1;
