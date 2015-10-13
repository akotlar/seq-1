use 5.10.0;
use strict;
use warnings;

package Seq::Role::Serialize;
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

use Data::Dump qw/ dump /;

my $tc_regex = qr{HashRef|ArrayRef};

sub header_attr {
  my $self = shift;
  
  my %hash;

  for my $attr ( $self->meta->get_all_attributes ) {
    my $name = $attr->name;
    my $type_constraint = $attr->type_constraint;
    if ( defined $self->$name ) {
      next if ( $type_constraint =~ m/$tc_regex/ or $name eq 'abs_pos');
      $hash{$name} = $self->$name;
    }
  }
  return \%hash;
}

sub as_href_with_NAs {
  my $self = shift;
  my %obj  = ();
  for my $attr ( $self->meta->get_all_attributes ) {
    my $name            = $attr->name;
    my $type_constraint = $attr->type_constraint;
    #  say join( ". .", $name, $type_constraint );
    #  say "this attrib: " . $attr->name . " has value: ";
    #  p $self->$name;
    if ( defined $self->$name ) {
      if ( $type_constraint eq 'HashRef' ) {
        map { $obj{"$name.$_"} = $self->$name->{$_} } keys %{ $self->$name };
      }
      elsif ( $type_constraint eq 'ArrayRef' ) {
        $obj{$name} = join( ";", @{ $self->$name } );
      }
      else {
        $obj{$name} = $self->$name;
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
