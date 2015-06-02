use 5.10.0;
use strict;
use warnings;

package Seq::Config::GenomeSizedTrack;
# ABSTRACT: Configure a genome sized track
# VERSION

use Moose 2;
use Moose::Util::TypeConstraints;

use namespace::autoclean;
use Scalar::Util qw/ reftype /;

use DDP;

enum GenomeSizedTrackType => [ 'genome', 'score', 'cadd' ];

my ( @idx_codes, @idx_base, @idx_in_gan, @idx_in_gene, @idx_in_exon, @idx_in_snp );
my %base_char_2_txt = ( '0' => 'N', '1' => 'A', '2' => 'C', '3' => 'G', '4' => 'T' );
my @in_gan  = qw/ 0 8 /; # is gene annotated
my @in_exon = qw/ 0 16 /;
my @in_gene = qw/ 0 32 /;
my @in_snp  = qw/ 0 64 /;

# we will use 0 to indicate absence and undef to indicate an error
for ( my $i = 0; $i < 256; $i++ ) {
  $idx_codes[$i] = $idx_base[$i] = $idx_in_gan[$i] = $idx_in_gene[$i] =
    $idx_in_exon[$i] = $idx_in_snp[$i] = undef;
}

foreach my $base_char ( keys %base_char_2_txt ) {
  foreach my $snp (@in_snp) {
    foreach my $gene (@in_gene) {
      foreach my $exon (@in_exon) {
        foreach my $gan (@in_gan) {
          my $char_code = $base_char + $gan + $gene + $exon + $snp;
          my $txt_base  = $base_char_2_txt{$base_char};
          $idx_base[$char_code]    = $txt_base;
          $idx_in_gan[$char_code]  = ($gan) ? 1 : 0;
          $idx_in_gene[$char_code] = ($gene) ? 1 : 0;
          $idx_in_exon[$char_code] = ($exon) ? 1 : 0;
          $idx_in_snp[$char_code]  = ($snp) ? 1 : 0;
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

has next_chr => (
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
  handles => {
    all_local_files  => 'elements',
    first_local_file => 'shift',
  },
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

# for conservation scores
has score_min => (
  is  => 'ro',
  isa => 'Num',
);

has score_max => (
  is  => 'ro',
  isa => 'Num',
);

has score_R => (
  is  => 'ro',
  isa => 'Num'
);

has _score_beta => (
  is      => 'ro',
  isa     => 'Num',
  lazy    => 1,
  builder => '_build_score_beta',
);

has _score_lu => (
  is      => 'ro',
  isa     => 'HashRef',
  traits  => ['Hash'],
  lazy    => 1,
  handles => { get_score_lu => 'get', },
  builder => '_build_score_lu',
);

sub _build_score_lu {
  my $self = shift;
  p $self->score_R;
  p $self->score_min;
  p $self->score_max;
  p $self->_score_beta;

  my %score_lu =
    map { $_ => ( ( ( $_ - 1 ) / $self->_score_beta ) + $self->score_min ) }
    ( 1 .. 254 );
  $score_lu{'0'} = 'NA';

  return \%score_lu;
}

sub _build_score_beta {
  my $self = shift;
  return ( ( $self->score_R - 1 ) / ( $self->score_max - $self->score_min ) );
}

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

# no longer needed as the building is moved to genome_hasher.c
# sub get_idx_code {
#   my $self = shift;
#   my ( $base, $in_gan, $in_gene, $in_exon, $in_snp ) = @_;
#   return $idx_codes{$base}{$in_gan}{$in_gene}{$in_exon}{$in_snp};
# }

sub get_idx_base {
  my ( $self, $char ) = @_;
  return $idx_base[$char];
}

sub get_idx_in_gan {
  my ( $self, $char ) = @_;
  return $idx_in_gan[$char];
}

sub get_idx_in_gene {
  my ( $self, $char ) = @_;
  return $idx_in_gene[$char];
}

sub get_idx_in_exon {
  my ( $self, $char ) = @_;
  return $idx_in_exon[$char];
}

sub get_idx_in_snp {
  my ( $self, $char ) = @_;
  return $idx_in_snp[$char];
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

sub BUILDARGS {
  my $class = shift;
  my $href  = $_[0];
  if ( scalar @_ > 1 || reftype($href) ne "HASH" ) {
    confess "Error: $class expects hash reference.\n";
  }
  else {
    my %hash;
    if ( $href->{type} eq "score" ) {
      if ( $href->{name} eq "phastCons" ) {
        $hash{score_R}   = 254;
        $hash{score_min} = 0;
        $hash{score_max} = 1;
      }
      elsif ( $href->{name} eq "phyloP" ) {
        $hash{score_R}   = 254;
        $hash{score_min} = -30;
        $hash{score_max} = 30;
      }
    }

    # if score_R, score_min, or score_max are set by the caller then the
    # following will override it
    for my $attr ( keys %$href ) {
      $hash{$attr} = $href->{$attr};
    }
    return $class->SUPER::BUILDARGS( \%hash );
  }
}

__PACKAGE__->meta->make_immutable;

1;
