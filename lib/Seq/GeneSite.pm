use 5.10.0;
use strict;
use warnings;

package Seq::GeneSite;
# ABSTRACT: Class for seralizing gene sites
# VERSION

use Moose 2;
use Moose::Util::TypeConstraints;

use namespace::autoclean;

#<<< No perltidy
my %Eu_codon_2_aa = (
    "AAA" => "K", "AAC" => "N", "AAG" => "K", "AAT" => "N",
    "ACA" => "T", "ACC" => "T", "ACG" => "T", "ACT" => "T",
    "AGA" => "R", "AGC" => "S", "AGG" => "R", "AGT" => "S",
    "ATA" => "I", "ATC" => "I", "ATG" => "M", "ATT" => "I",
    "CAA" => "Q", "CAC" => "H", "CAG" => "Q", "CAT" => "H",
    "CCA" => "P", "CCC" => "P", "CCG" => "P", "CCT" => "P",
    "CGA" => "R", "CGC" => "R", "CGG" => "R", "CGT" => "R",
    "CTA" => "L", "CTC" => "L", "CTG" => "L", "CTT" => "L",
    "GAA" => "E", "GAC" => "D", "GAG" => "E", "GAT" => "D",
    "GCA" => "A", "GCC" => "A", "GCG" => "A", "GCT" => "A",
    "GGA" => "G", "GGC" => "G", "GGG" => "G", "GGT" => "G",
    "GTA" => "V", "GTC" => "V", "GTG" => "V", "GTT" => "V",
    "TAA" => "*", "TAC" => "Y", "TAG" => "*", "TAT" => "Y",
    "TCA" => "S", "TCC" => "S", "TCG" => "S", "TCT" => "S",
    "TGA" => "*", "TGC" => "C", "TGG" => "W", "TGT" => "C",
    "TTA" => "L", "TTC" => "F", "TTG" => "L", "TTT" => "F"
);

enum GeneAnnotationType => [ '5UTR', 'Coding', '3UTR', 'non-coding RNA',
                             'Splice Donor', 'Splice Acceptor' ];
enum StrandType         => [ '+', '-' ];
#>>>

has abs_pos => (
  is        => 'rw',
  isa       => 'Int',
  required  => 1,
  clearer   => 'clear_abs_pos',
  predicate => 'has_abs_pos',
);

has base => (
  is        => 'rw',
  isa       => 'Str',
  required  => 1,
  clearer   => 'clear_base',
  predicate => 'has_base',
);

has transcript_id => (
  is        => 'rw',
  isa       => 'Str',
  required  => 1,
  clearer   => 'clear_name',
  predicate => 'has_name',
);

has annotation_type => (
  is        => 'rw',
  isa       => 'GeneAnnotationType',
  required  => 1,
  clearer   => 'clear_annotation_type',
  predicate => 'has_annotation_type',
);

has strand => (
  is        => 'rw',
  isa       => 'StrandType',
  required  => 1,
  clearer   => 'clear_strand',
  predicate => 'has_strand',
);

# codon at site
has codon_seq => (
  is        => 'rw',
  isa       => 'Maybe[Str]',
  default   => sub { undef },
  clearer   => 'clear_codon',
  predicate => 'has_codon',
);

# bp position within the codon
has codon_number => (
  is        => 'rw',
  isa       => 'Maybe[Int]',
  default   => sub { undef },
  clearer   => 'clear_codon_site_pos',
  predicate => 'has_codon_site_pos',
);

# amino acid residue # from start of transcript
has codon_position => (
  is        => 'rw',
  isa       => 'Maybe[Int]',
  default   => sub { undef },
  clearer   => 'clear_aa_residue_pos',
  predicate => 'has_aa_residue_pos',
);

has aa_residue => (
  is      => 'ro',
  lazy    => 1,
  builder => '_set_aa_residue',
);

has alt_names => (
  is      => 'ro',
  isa     => 'HashRef',
  traits  => ['Hash'],
  handles => { no_alt_names => 'is_empty', },
);

has error_code => (
  is        => 'rw',
  isa       => 'ArrayRef',
  required  => 1,
  clearer   => 'clear_error_code',
  predicate => 'has_error_code',
  traits    => ['Array'],
  handles   => { no_error_code => 'is_empty', },
);

sub _set_aa_residue {
  my $self = shift;
  if ( $self->codon_seq ) {
    return $Eu_codon_2_aa{ $self->codon_seq };
  }
  else {
    return undef;
  }
}

sub as_href {
  my $self = shift;
  my %hash;

  for my $attr (
    qw( abs_pos base transcript_id annotation_type strand codon_seq
    codon_number codon_position aa_residue error_code alt_names )
    )
  {
    my $empty_attr = "no_" . $attr;
    if ( $self->$attr ) {
      if ( $self->meta->has_method($empty_attr) ) {
        $hash{$attr} = $self->$attr unless $self->$empty_attr;
      }
      else {
        $hash{$attr} = $self->$attr;
      }
    }
  }
  return \%hash;
}

__PACKAGE__->meta->make_immutable;

1;
