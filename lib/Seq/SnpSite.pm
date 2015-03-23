use 5.10.0;
use strict;
use warnings;

package Seq::SnpSite;
# ABSTRACT: Builds a snp track using dbSnp data, derived from UCSC
# VERSION

use Moose 2;

use namespace::autoclean;

has abs_pos => (
  is        => 'ro',
  isa       => 'Int',
  required  => 1,
  clearer   => 'clear_abs_pos',
  predicate => 'has_abs_pos',
);

has snp_id => (
  is        => 'ro',
  isa       => 'Str',
  required  => 1,
  clearer   => 'clear_snp_id',
  predicate => 'has_snp_id',
);

has feature => (
  is        => 'rw',
  isa       => 'HashRef',
  clearer   => 'clear_feature',
  predicate => 'has_feature',
  traits    => ['Hash'],
  handles   => {
    set_feature  => 'set',
    get_feature  => 'get',
    all_features => 'elements',
    no_feature   => 'is_empty',
  },
);

sub as_href {
  my $self = shift;
  my %hash;

  for my $attr (qw( abs_pos snp_id feature )) {
    if ( $attr eq "feature" ) {
      $hash{$attr} = $self->$attr unless $self->no_feature;
    }
    else {
      $hash{$attr} = $self->$attr;
    }
  }
  return \%hash;
}

__PACKAGE__->meta->make_immutable;

1;
