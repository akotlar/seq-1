use 5.10.0;
use strict;
use warnings;

package Seq::Site::Snp;
# ABSTRACT: A class for seralizing Snp sites
# VERSION

use Moose 2;

use namespace::autoclean;

my @attributes = qw( abs_pos ref_base snp_id snp_feature );

extends 'Seq::Site';
with 'Seq::Role::Serialize';

has snp_id => (
  is        => 'ro',
  isa       => 'Str',
  clearer   => 'clear_snp_id',
  predicate => 'has_snp_id',
);

has snp_feature => (
  is        => 'rw',
  isa       => 'HashRef',
  clearer   => 'clear_feature',
  predicate => 'has_feature',
  traits    => ['Hash'],
  handles   => {
    set_snp_feature  => 'set',
    get_snp_feature  => 'get',
    all_snp_features => 'elements',
    no_snp_feature   => 'is_empty',
  },
);

# this function is really for storing in mongo db collection
sub as_href {
  my $self = shift;
  my %hash;

  for my $attr (@attributes) {
    if ( $attr eq "feature" ) {
      $hash{$attr} = $self->$attr unless $self->no_feature;
    }
    else {
      $hash{$attr} = $self->$attr;
    }
  }
  return \%hash;
}

sub seralizable_attributes {
  return @attributes;
}

__PACKAGE__->meta->make_immutable;

1;
