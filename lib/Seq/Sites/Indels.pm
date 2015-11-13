use 5.10.0;
use strict;
use warnings;
package Seq::Sites::Indels;

use Moose;

use Seq::Site::Indel;
use Seq::Site::Indel::Type;
use Seq::KCManager;

has db => (
  is => 'ro',
  isa => 'Seq::KCManager',
);

has alleles => (
  is => 'ro',
  isa => 'ArrayRef[Indel]',
  coerce => 1,
  traits => {
    allAlleles => 'elements',
  },
);

has annotations => (
  is => 'rw',
  required => 0,
  default => sub{[]},
  isa => 'ArrayRef[Site::Site]',
  traits => ['Array'],
  handles => {
    allAnnotations => 'elements',
  }
);

#basePosData is the current base; for a SNP this is fine, and for single
#base deletions this is fine, for -(1+N) deletions or +N insertions, not fine
sub findGeneData {
  my ($self, $basePosDataAref, $abs_pos, $db) = @;

  my @positions;
  my $dataAref;
  for my $allele ($self->alleles) {
    if($allele->indType eq '-') {
      if($allele->indLength > 1) {
        @positions = ($abs_pos - $allele->indLength .. $abs_pos - 1);
        $dataAref = $db->get_bulk(@positions);
        say "We got for dataAref";
        p $dataAref;
        push @$dataAref, $basePosDataAref;
      } else {
        $dataAref = [$basePosData];
      }
    } 
    # else {
    #   # ins
    #   @positions = ($abs_pos .. $abs_pos - 1)
    #   $dataAref = $db->get_bulk(@positions);
    #   say "We got for dataAref";
    #   p $dataAref;
    # }
  }
}


sub _set_annotation_type {
  my $self = shift;
  my $frame = $self->indLength % 3 ? 'FrameShift' : 'InFrame';

  my $str = ($self->indType eq '-' ? 'Del' : 'Ins' ) . "-$frame-";
  #first capture gross
  #covers 3UTR, 5UTR, and all other GeneSiteType 's enum'd
  my $annotation_type = $str . $self->site_type . ";"; #or could interpolate ${}

  if($self->site_type eq 'Coding') {
    if($self->codon_number == 1) {
      $annotation_type .= $str . "StartLoss;"; #or could interpolate
    }
    if ($self->ref_aa_residue eq '*' ) {
      $annotation_type .= $str . "StopLoss;";
    }
  }
  chop $annotation_type;

  return $annotation_type;
}

__PACKAGE__->meta->make_immuatable;
1;