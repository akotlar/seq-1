use 5.10.0;
use strict;
use warnings;

package Seq::Config::GenomeSizedTrack;
# ABSTRACT: Configure a genome sized track
# VERSION

use Moose 2;
use Moose::Util::TypeConstraints;

use Carp qw/ confess /;
use namespace::autoclean;
use Scalar::Util qw/ reftype /;

enum GenomeSizedTrackType => [ 'genome', 'score', ];

my ( %idx_codes, %idx_base, %idx_in_gan, %idx_in_gene, %idx_in_exon, %idx_in_snp );
{
  my @bases      = qw( A C G T N );
  my @annotation = qw( 0 1 );
  my @in_exon    = qw( 0 1 );
  my @in_gene    = qw( 0 1 );
  my @in_snp     = qw( 0 1 );
  my @char       = ( 0 .. 255 );
  my $i          = 0;

  foreach my $base (@bases) {
    foreach my $gan (@annotation) {
      foreach my $gene (@in_gene) {
        foreach my $exon (@in_exon) {
          foreach my $snp (@in_snp) {
            my $code = $char[$i];
            $i++;
            $idx_codes{$base}{$gan}{$gene}{$exon}{$snp} = $code;
            $idx_base{$code} = $base;
            $idx_in_gan{$code}  = $base if $gan;
            $idx_in_gene{$code} = $base if $gene;
            $idx_in_exon{$code} = $base if $exon;
            $idx_in_snp{$code}  = $base if $snp;
          }
        }
      }
    }
  }
}

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

#
# for processing scripts
#
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

  confess "get_idx_code() expects base, in_gan, in_gene, in_exon, and in_snp"
    unless $base =~ m/[ACGTN]/
    and defined $in_gan
    and defined $in_gene
    and defined $in_exon
    and defined $in_snp;

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

__PACKAGE__->meta->make_immutable;

1;
