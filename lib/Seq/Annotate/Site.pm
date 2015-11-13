use 5.10.0;
use strict;
use warnings;

package Seq::Annotate::Site;

our $VERSION = '0.001';

# ABSTRACT: Base class for seralizing reference annotations
# VERSION

=head1 DESCRIPTION

  @class B<Seq::Annotate::Site>
  #TODO: Check description

  @example

Used in: Seq::Annotate

=cut

use Moose 2;
use Moose::Util::TypeConstraints;

use Carp qw/ confess /;
use namespace::autoclean;
use DDP;

use Seq::Site::Snp;
use Seq::Site::Annotation;

with 'Seq::Role::Serialize';

enum GenomicType => [ 'Exonic', 'Intronic', 'Intergenic' ];

has abs_pos      => ( is => 'ro', isa => 'Int',          required => 1, );
has chr          => ( is => 'ro', isa => 'Str',          required => 1, );
has genomic_type => ( is => 'ro', isa => 'GenomicType',  required => 1, );
has pos          => ( is => 'ro', isa => 'Int',          required => 1, );
has ref_base     => ( is => 'ro', isa => 'Str',          required => 1, );
has scores       => ( is => 'ro', isa => 'HashRef[Str]', default  => sub { {} }, lazy => 1);
has warning      => ( is => 'ro', isa => 'Str',          default  => 'NA', lazy => 1);

# the objects stored in gene_data really only need to do as_href_with_NAs(),
# which is a method in Seq::Role::Seralize
has gene_data => (
  traits   => ['Array'],
  is       => 'ro',
  isa      => 'ArrayRef[Maybe[Seq::Site::Gene]]',
  required => 1,
  handles  => { all_gene_obj => 'elements', },
);

# the objects stored in snp_data really only need to do as_href_with_NAs(),
# which is a method in Seq::Role::Seralize
has snp_data => (
  traits   => ['Array'],
  is       => 'ro',
  isa      => 'ArrayRef[Maybe[Seq::Site::Snp]]',
  required => 1,
  handles  => { all_snp_obj => 'elements', },
);

sub attrs {
  state $attrs = ['chr', 'pos', 'var_type', 'ref_base', 'genomic_type', 'warning'];
  return $attrs;
}

sub as_href {
  my $self = shift;

  my %hash;

  for my $attr ( @{ $self->attrs } ) {
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
        $merge{$attr} = "$old_val;$new_val"; #http://www.perlmonks.org/?node_id=964608
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
