use 5.10.0;
use strict;
use warnings;

package Seq::Role::Serialize;

our $VERSION = '0.001';

# ABSTRACT: A moose role for serializing data
# VERSION

=head1 DESCRIPTION

  @role B<Seq::Role::Serialize>
  #TODO: Check description

  @example

Used in:
=for :list
* Seq/Site/Annotation.pm
* Seq/Site/Snp.pm

Extended by: None

=cut

use Moose::Role 2;

use Cpanel::JSON::XS;
use namespace::autoclean;
use Scalar::Util qw/ reftype /;

my $tc_regex = qr{HashRef|ArrayRef};

# header_attr() returns a hash reference of the header, which is defined as
# all attributes that are not references to hashes or arrays or abs_pos
# attribute. The rationale for this is that the hashes (presently not using
# any array references) only hold "features" which may vary depending on
# the assembly specification. In Seq::Annotate the _build_header() will
# query the gene and snp tracks to build all features using the actual data
# in the assembly.
sub header_attr {
  my $self = shift;

  my %hash;

  for my $attr ( $self->meta->get_all_attributes ) {
    my $name            = $attr->name;
    my $type_constraint = $attr->type_constraint;
    if ( defined $self->$name ) {
      next if ( $type_constraint =~ m/$tc_regex/ or $name eq 'abs_pos' );
      $hash{$name} = $self->$name;
    }
  }
  return \%hash;
}

sub as_href_with_NAs {
  my $self = shift;
  my %obj  = ();
  my $name;
  my $selfAttr; #declared here to easy garbage collection
  for my $attr ( $self->meta->get_all_attributes ) {
    $name     = $attr->name;
    $selfAttr = $self->$name;
    # Attempting optimization; this is a bottleneck;
    # At this point, all attrs sohuld have been populated, so ref HASH / ARRAY should be safe
    # my $type_constraint = $attr->type_constraint;
    if ( defined $selfAttr ) {
      if ( ref $selfAttr eq 'HASH' ) { #if ( ref $type_constraint eq 'HashRef' ) {
        map { $obj{"$name.$_"} = $selfAttr->{$_} } keys %{$selfAttr};
      }
      elsif ( ref $selfAttr eq 'ARRAY' ) {
        $obj{$name} = join( ";", @{$selfAttr} );
      }
      else {
        $obj{$name} = $selfAttr;
      }
    }
    else {
      $obj{$name} = 'NA';
    }
  }
  return \%obj;
}

sub as_array_ref_with_NAs {
  my $self = shift;
  my @array = map { $self->as_href_with_NAs->{$_} }
    sort { $a cmp $b } keys %{ $self->as_href_with_NAs };
  return \@array;
}

sub as_json_with_NAs {
  my $self = shift;
  return encode_json( $self->as_href_with_NAs );
}

sub as_yaml_with_NAs {
  my $self = shift;
  return Dump( $self->as_href_with_NAs );
}

no Moose::Role;

1;
