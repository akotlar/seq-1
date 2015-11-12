use 5.10.0;
use strict;
use warnings;

package Seq::Site::Indel;

our $VERSION = '0.001';

# ABSTRACT: Class for seralizing indel sites
# VERSION

use Moose 2;

use namespace::autoclean;
use Moose::Util::TypeConstraints;
use DDP;

extends 'Seq::Site::Gene';
with 'Seq::Role::Serialize';

#can't use type str, because -1 is a number, could coerce, but why?
#will fail early if input bad anyway
has minor_allele => (
  is       => 'ro',
  required => 1,
);

has new_codon_seq => (
  is      => 'ro',
  isa     => 'Maybe[Str]',
  lazy    => 1,
  builder => '_set_new_codon_seq',
);

has new_aa_residue => (
  is      => 'ro',
  isa     => 'Maybe[Str]',
  lazy    => 1,
  builder => '_set_new_aa_residue',
);

has annotation_type => (
  is       => 'rw',
  isa      => 'Str',
  lazy     => 1,
  builder  => '_set_annotation_type'
);

enum indTypes => [qw(- +)];
has indType => (
  is => 'ro',
  isa => 'indTypes',
  lazy => 1,
  builder => '_build_indel_type',
);

#@returns - or +
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
#Thomas, haven't done anything with the next 2 methods yet
#have $self->indType if want to use this
sub _set_new_codon_seq {
  my $self = shift;

  if ( $self->ref_codon_seq ) {
    return $self->indType . $self->indLength;
  }
  else {
    return;
  }
}

sub _set_new_aa_residue {
  my $self = shift;

  if ( $self->new_codon_seq ) {
    return $self->indType . $self->indLength;
  }
  else {
    return;
  }
}

sub BUILD {
  my $self = shift;

  $self->annotation_type;
};

state $frames = ['InFrame', 'FrameShift'];
sub _set_annotation_type {
  my $self = shift;
  my $frame = $frames->[$self->indLength % 3];
  my $str = $self->indType eq '-' ? 'Del' : 'Ins' ."$frame";
  #first capture gross
  #covers 3UTR, 5UTR, and all other GeneSiteType 's enum'd
  my $annotation_type = $str .'-'. $self->site_type . ";"; #or could interpolate ${}

  if($self->site_type eq 'Coding') {
    if($self->codon_number == 1) {
      $annotation_type .= $str .'-'. "StartLoss;"; #or could interpolate
    }
    if ($self->ref_aa_residue eq '*' ) {
      $annotation_type .= $str .'-'. "StopLoss;";
    }
  }
  say "annotation_type del is";
  p $annotation_type;
  chop $annotation_type;
  return $annotation_type;
}

__PACKAGE__->meta->make_immutable;

1;
