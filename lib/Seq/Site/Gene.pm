use 5.10.0;
use strict;
use warnings;

package Seq::Site::Gene;
# ABSTRACT: Class for seralizing gene sites
# VERSION

use Moose 2;
use Moose::Util::TypeConstraints;

use namespace::autoclean;

extends 'Seq::Site';

#<<< No perltidy
my @attributes = qw( abs_pos ref_base transcript_id site_type strand ref_codon_seq
    codon_number codon_position ref_aa_residue error_code alt_names );

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

enum GeneSiteType => [ '5UTR', 'Coding', '3UTR', 'non-coding RNA',
                       'Splice Donor', 'Splice Acceptor' ];
enum StrandType   => [ '+', '-' ];
#>>>

has transcript_id => (
  is        => 'ro',
  isa       => 'Str',
  required  => 1,
  predicate => 'has_name',
);

has site_type => (
  is        => 'ro',
  isa       => 'GeneSiteType',
  required  => 1,
  predicate => 'has_site_type',
);

has strand => (
  is        => 'ro',
  isa       => 'StrandType',
  required  => 1,
  predicate => 'has_strand',
);

# amino acid residue # from start of transcript
has codon_number => (
  is        => 'ro',
  isa       => 'Maybe[Int]',
  default   => sub { undef },
  predicate => 'has_codon_site_pos',
);


has codon_position => (
  is        => 'ro',
  isa       => 'Maybe[Int]',
  default   => sub { undef },
  predicate => 'has_aa_residue_pos',
);

has alt_names => (
  is      => 'ro',
  isa     => 'HashRef',
  traits  => ['Hash'],
  handles => { no_alt_names => 'is_empty', },
);

has error_code => (
  is        => 'ro',
  isa       => 'ArrayRef',
  predicate => 'has_error_code',
  traits    => ['Array'],
  handles   => { no_error_code => 'is_empty', },
);

# the following are attributs with respect to the reference genome

# codon at site
has ref_codon_seq => (
  is        => 'ro',
  isa       => 'Maybe[Str]',
  default   => sub { undef },
  predicate => 'has_codon',
);

has ref_aa_residue => (
  is      => 'ro',
  isa     => 'Maybe[Str]',
  lazy    => 1,
  builder => '_set_ref_aa_residue',
);

sub codon_2_aa {
  my ( $self, $codon ) = @_;
  if ($codon) {
    return $Eu_codon_2_aa{$codon};
  }
  else {
    return;
  }
}

sub _set_ref_aa_residue {
  my $self = shift;
  if ( $self->ref_codon_seq ) {
    return $self->codon_2_aa( $self->ref_codon_seq );
  }
  else {
    return;
  }
}

# this function is really for storing in mongo db collection
sub as_href {
  my $self = shift;
  my %hash;

  for my $attr (@attributes) {
    my $empty_attr = "no_" . $attr;
    if ( $self->meta->has_method($empty_attr) ) {
      $hash{$attr} = $self->$attr unless $self->$empty_attr;
    }
    elsif ( defined $self->$attr ) {
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
