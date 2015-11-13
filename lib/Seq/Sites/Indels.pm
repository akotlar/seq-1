use 5.10.0;
use strict;
use warnings;
package Seq::Sites::Indels;

use Moose;
use DDP;

use Seq::Site::Indel;
use Seq::Site::Indel::Type;

has alleles => (
  is => 'ro',
  isa => 'Indels',
  coerce => 1,
  traits => ['Array'],
  handles => {
    allAlleles => 'elements',
  },
  required => 1,
);

  # traits => ['Array'],
  # coerce => 1,
  # handles => {
  #   allAlleles => 'elements',
  # },
  # required => 1,

has annotations => (
  is => 'rw',
  required => 0,
  default => sub{[]},
  isa => 'ArrayRef',
  traits => ['Array'],
  handles => {
    allAnnotations => 'elements',
  },
  init_arg => undef,
);

#basePosData is the current base; for a SNP this is fine, and for single
#base deletions this is fine, for -(1+N) deletions or +N insertions, not fine
#The whole $basePosDataAref routine, which checked for indLenght > 1, then 
#appended already fetched one position data...could make things faster, 
#or could just be a microopt that's fragile.. removed for now
sub findGeneData {
  my ($self, $basePosDataAref, $abs_pos, $db) = @_;

  my @data;
  my $annotationType;
  for my $allele ($self->allAlleles) {
    
    say "allele is";
    p $allele;
    say "indType is";
    p $allele->indType;
    say "indLength is";
    p $allele->indLength;

    if($allele->indType eq '-') {
      #inclusive of current base
      @data = $db->db_get([$abs_pos - $allele->indLength + 1 .. $abs_pos] );
    } else {
      #exclusive of current base
      @data = $db->get_bulk([$abs_pos + 1 .. $abs_pos + $allele->indLength] );
    }
    say "We got for dataAref";
    
    $annotationType = $allele->typeName . '-' . $allele->frameType . '[' . 
      __buildAnnotationStr(\@data).']';

    
  }
}

#TODO: split this off into separate Type, separate file
#Tracks Thomas' function, gets "worst" kind; in order
state $site_types = ['Coding', '5UTR', '3UTR', 'Splice Acceptor', 'Splice Donor'];
state $delim = '|'; #can't be ;
#Thomas, I noticed that we can potentially have many interesting variants
#Say indels that hit start and stop, so I want to grab them all, in order
#It seems like a waste not to if we're already 90% of the way there; people can 
#ignore anything after the first delim if the wish to just see the most serious
sub __buildAnnotationStr {
  my $sitesAref = shift;

  my $annotationStr = '';
  my $sugar = '';
  my $index;
  for my $siteType (@$siteTypes) {
    for my $geneRecordAref (@sitesAref) {
      for my $transcriptHref (@$geneRecordAref) {
        if($index == 0) { 
          if(defined $transcriptHref->ref_aa_residue && $transcriptHref->ref_aa_residue eq '*' ) {
            $sugar = 'StopLoss';
          } elsif ($transcriptHref->codon_number == 1) {
            $sugar = 'StartLoss';
          }
        } else {
          $sugar = $transcriptHref->site_type;
        }
        $annotationStr .= "$sugar|"; # a bit like fasta
      }
    }
    $index++;
  }
  chop $annotationStr;
  return $annotationStr;
}

# sub __buildAnnotationHash {
#   my $sitesAref = shift;

#   my $foundSiteType;
#   OUTER: for my $siteType (@$siteTypes) {
#     for my $transcriptAref (@sitesAref) {
#       for my $siteAref (@$transcriptAref) {
#         if($siteAref->site_type eq $siteType) {
#           $foundSiteType = $siteType;
#           last OUTER;
#         }
#       }
#     }
#   }
#   #I like to use indices, because underlying names can change, even case
#   if($foundSIteType eq $siteType->[0] ) {

#   }
# }

# sub _set_annotation_type {
#   my $self = shift;
#   my $frame = $self->indLength % 3 ? 'FrameShift' : 'InFrame';

#   my $str = ($self->indType eq '-' ? 'Del' : 'Ins' ) . "-$frame-";
#   #first capture gross
#   #covers 3UTR, 5UTR, and all other GeneSiteType 's enum'd
#   my $annotation_type = $str . $self->site_type . ";"; #or could interpolate ${}

#   if($self->site_type eq 'Coding') {
#     if($self->codon_number == 1) {
#       $annotation_type .= $str . "StartLoss;"; #or could interpolate
#     }
#     if ($self->ref_aa_residue eq '*' ) {
#       $annotation_type .= $str . "StopLoss;";
#     }
#   }
#   chop $annotation_type;

#   return $annotation_type;
# }
__PACKAGE__->meta->make_immutable;

1;