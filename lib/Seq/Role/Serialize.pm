use 5.10.0;
use strict;
use warnings;

package Seq::Role::Serialize;
# ABSTRACT: A moose role for serializing data
# VERSION

use Moose::Role 2;

use namespace::autoclean;

use Cpanel::JSON::XS;
use Scalar::Util qw/ reftype /;
use YAML::XS qw/ Dump /;

use DDP;

# not using this sub since we're asking the meta class about the attributes
requires qw/ seralizable_attributes  /;

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
