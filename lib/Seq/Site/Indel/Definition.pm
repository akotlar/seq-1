use strict;
use warnings;
package Seq::Site::Indel::Definition;

use Moose;
use Moose::Util::TypeConstraints;

has minor_allele => (
  is       => 'ro',
  isa => 'Str',
  required => 1,
);

# will hard crash if bad input, as soon as it's called
enum IndTypes => [qw(- +)];
has indType => (
  is => 'ro',
  isa => 'IndTypes',
  lazy => 1,
  builder => '_build_indel_type',
);

sub _build_indel_type {
  my $self = shift;
  #cast as str to substr in case of -N
  return substr("".$self->minor_allele, 0, 1); 
}

has indLength => (
  is => 'ro',
  isa => 'Num',
  lazy => 1,
  builder => '_build_indel_length',
);

sub _build_indel_length {
  my $self = shift;
  return substr($self->minor_allele, 1) if $self->indType eq '-'; #a number
  return length($self->minor_allele) - 1 if $self->indType eq '+'; #a string
}

enum FrameTypes => [qw(FrameShift InFrame)];
has frameType => (
  is => 'ro',
  isa => 'FrameTypes',
  lazy => 1,
  builder => '_buildFrameType',
);

sub _buildFrameType {
  my $self = shift;
  my $frame = $self->indLength % 3 ? 'FrameShift' : 'InFrame';
};

has typeName => (
  is => 'ro',
  isa => 'Str',
  lazy => 1,
  builder => '_buildTypeName',
);

sub _buildTypeName {
  my $self = shift;
  return $self->indType eq '-' ? 'Del' : 'Ins';
}

# #we expect a single argument, a scalar or scalar ref
# around BUILDARGS => sub {
#   my $orig = shift;
#   my $class = shift;

#   if (ref $_[0] eq 'HASH') {
#     $class->$orig($_[0]);
#   }

#   my $allele = $_[0];
#   #alternatively can let hard crash
#   if(!$allele) {
#     confess "Error: $class expects simple scalar or scalar ref, falsy passed";
#   }
#   if(ref $allele) {
#     if(ref $allele ne 'SCALAR') { confess "$class accepts only scalar refs"};
#     $allele = $$allele;
#   }

#   $class->$orig(minor_allele => $allele);
# };

__PACKAGE__->meta->make_immutable;
1;