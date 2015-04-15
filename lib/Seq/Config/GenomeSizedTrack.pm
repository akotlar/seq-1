use 5.10.0;
use strict;
use warnings;

package Seq::Config::GenomeSizedTrack;
# ABSTRACT: Configure a genome sized track
# VERSION

use Moose 2;
use Moose::Util::TypeConstraints;

use namespace::autoclean;

enum GenomeSizedTrackType => [ 'genome', 'score', ];

my ( %idx_codes, %idx_base, %idx_in_gan, %idx_in_gene, %idx_in_exon, %idx_in_snp );
my %base_char_2_txt = ( '0' => 'A', '1' => 'C', '2' => 'G', '3' => 'T', '4' => 'N' );
my @base_chars = qw/ 0 1 2 3 4 /;
my @in_gan  = qw/ 0 8 /; # is gene annotated
my @in_exon = qw/ 0 16 /;
my @in_gene = qw/ 0 32 /;
my @in_snp  = qw/ 0 64 /;

foreach my $base_char (@base_chars) {
  foreach my $gan (@in_gan) {
    foreach my $gene (@in_gene) {
      foreach my $exon (@in_exon) {
        foreach my $snp (@in_snp) {
          my $char_code = $base_char + $gan + $gene + $exon + $snp;
          my $txt_base  = $base_char_2_txt{$base_char};
          $idx_codes{$txt_base}{$gan}{$gene}{$exon}{$snp} = $char_code;
          $idx_base{$char_code} = $txt_base;
          $idx_in_gan{$char_code}  = $txt_base if $gan;
          $idx_in_gene{$char_code} = $txt_base if $gene;
          $idx_in_exon{$char_code} = $txt_base if $exon;
          $idx_in_snp{$char_code}  = $txt_base if $snp;
        }
      }
    }
  }
}

# basic features
has name => ( is => 'ro', isa => 'Str', required => 1, );
has type => ( is => 'ro', isa => 'GenomeSizedTrackType', required => 1, );
has genome_chrs => (
  is       => 'ro',
  isa      => 'ArrayRef[Str]',
  traits   => ['Array'],
  required => 1,
  handles  => { all_genome_chrs => 'elements', },
);
has _next_chrs => (
  is      => 'ro',
  isa     => 'HashRef',
  traits  => ['Hash'],
  lazy    => 1,
  builder => '_build_next_chr',
  handles => { get_next_chr => 'get', },
);

# file stuff
has genome_index_dir => ( is => 'ro', isa => 'Str', );
has local_dir        => ( is => 'ro', isa => 'Str', );
has local_files      => (
  is      => 'ro',
  isa     => 'ArrayRef[Str]',
  traits  => ['Array'],
  handles => { all_local_files => 'elements', },
);
has remote_dir => ( is => 'ro', isa => 'Str' );
has remote_files => (
  is     => 'ro',
  isa    => 'ArrayRef[Str]',
  traits => ['Array'],
);

# for processing scripts
has proc_init_cmds => (
  is     => 'ro',
  isa    => 'ArrayRef[Str]',
  traits => ['Array'],
);
has proc_chrs_cmds => (
  is     => 'ro',
  isa    => 'ArrayRef[Str]',
  traits => ['Array'],
);
has proc_clean_cmds => (
  is     => 'ro',
  isa    => 'ArrayRef[Str]',
  traits => ['Array'],
);

sub _build_next_chr {
  my $self = shift;

  my %next_chrs;
  my @chrs = $self->all_genome_chrs;
  for my $i ( 0 .. $#chrs ) {
    if ( defined $chrs[ $i + 1 ] ) {
      $next_chrs{ $chrs[$i] } = $chrs[ $i + 1 ];
    }
  }
  return \%next_chrs;
}

sub get_idx_code {
  my $self = shift;
  my ( $base, $in_gan, $in_gene, $in_exon, $in_snp ) = @_;
  my $code //= $idx_codes{$base}{$in_gan}{$in_gene}{$in_exon}{$in_snp};
  return $code;
}

sub get_idx_base {
  my ( $self, $char ) = @_;
  my $base //= $idx_base{$char};
  return $base;
}

sub get_idx_in_gan {
  my ( $self, $char ) = @_;
  my $code //= $idx_in_gan{$char};
  return $code;
}

sub get_idx_in_gene {
  my ( $self, $char ) = @_;
  my $code //= $idx_in_gene{$char};
  return $code;
}

sub get_idx_in_exon {
  my ( $self, $char ) = @_;
  my $code //= $idx_in_exon{$char};
  return $code;
}

sub get_idx_in_snp {
  my ( $self, $char ) = @_;
  my $code //= $idx_in_snp{$char};
  return $code;
}

sub in_gan_val {
  my $self = @_;
  return $in_gan[1];
}

sub in_exon_val {
  my $self = @_;
  return $in_exon[1];
}

sub in_gene_val {
  my $self = @_;
  return $in_gene[1];
}

sub in_snp_val {
  my $self = @_;
  return $in_snp[1];
}

__PACKAGE__->meta->make_immutable;

1;
