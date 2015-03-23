use 5.10.0;
use strict;
use warnings;

package Seq::Build;

use Moose 2;

use Carp qw/ croak /;
use namespace::autoclean;
use Scalar::Util qw/ reftype /;

use Seq::Build::SnpTrack;
use Seq::Build::GeneTrack;
use Seq::Build::GenomeSizedTrackChar;
use Seq::Build::GenomeSizedTrackStr;
use Seq::Config::SparseTrack;
use Seq::MongoManager;

with 'Seq::Role::ConfigFromFile', 'Seq::Role::IO';

has genome_name        => ( is => 'ro', isa => 'Str', required => 1, );
has genome_description => ( is => 'ro', isa => 'Str', required => 1, );
has genome_chrs        => (
  is       => 'ro',
  isa      => 'ArrayRef[Str]',
  traits   => ['Array'],
  required => 1,
  handles  => { all_genome_chrs => 'elements', },
);

# for now, `genome_raw_dir` is really not needed since the other tracks
#   specify a directory and file to use for each feature
has genome_raw_dir   => ( is => 'ro', isa => 'Str', required => 1, );
has genome_index_dir => ( is => 'ro', isa => 'Str', required => 1, );
has genome_str_track => (
  is       => 'ro',
  isa      => 'Seq::Build::GenomeSizedTrackStr',
  required => 1,
  handles  => [ 'get_abs_pos', 'get_base', 'build_genome', 'genome_length', ],
);
has genome_sized_tracks => (
  is      => 'ro',
  isa     => 'ArrayRef[Seq::Config::GenomeSizedTrack]',
  traits  => ['Array'],
  handles => {
    all_genome_sized_tracks => 'elements',
    add_genome_sized_track  => 'push',
  },
);
has snp_tracks => (
  is      => 'ro',
  isa     => 'ArrayRef[Seq::Config::SparseTrack]',
  traits  => ['Array'],
  handles => {
    all_snp_tracks => 'elements',
    add_snp_track  => 'push',
  },
);
has gene_tracks => (
  is      => 'ro',
  isa     => 'ArrayRef[Seq::Config::SparseTrack]',
  traits  => ['Array'],
  handles => {
    all_gene_tracks => 'elements',
    add_gene_track  => 'push',
  },
);
has host => (
  is      => 'ro',
  isa     => 'Str',
  default => '127.0.0.1',
);

sub build_index {
  my $self = shift;

  # build genome from fasta files (i.e., string)
  $self->build_genome;

  # make chr_len hash for binary genome
  my %chr_len = map { $_ => $self->get_abs_pos( $_, 1 ) } ( $self->all_genome_chrs );

  # build snp tracks
  my %snp_sites;
  if ( $self->snp_tracks ) {
    for my $snp_track ( $self->all_snp_tracks ) {
      my $record = $snp_track->as_href;
      $record->{genome_seq}       = $self->genome_str_track;
      $record->{genome_index_dir} = $self->genome_index_dir;
      $record->{genome_name}      = $self->genome_name;
      $record->{host}             = $self->host;
      $record->{mongo_connection} = Seq::MongoManager->new(
        {
          default_database => $self->genome_name,
          client_options   => { host => "mongodb://" . $self->host }
        }
      );
      my $snp_db     = Seq::Build::SnpTrack->new($record);
      my $sites_aref = $snp_db->build_snp_db;
      map { $snp_sites{$_}++ } @$sites_aref;
    }
  }

  # build gene tracks - these are gene annotation tracks downloaded from UCSC
  # e.g., knownGene
  my ( %flank_exon_sites, %exon_sites, %transcript_starts );
  for my $gene_track ( $self->all_gene_tracks ) {
    my $record = $gene_track->as_href;
    $record->{genome_track_str} = $self->genome_str_track;
    $record->{genome_index_dir} = $self->genome_index_dir;
    $record->{genome_name}      = $self->genome_name;
    $record->{mongo_connection} = Seq::MongoManager->new(
      {
        default_database => $self->genome_name,
        client_options   => { host => "mongodb://" . $self->host }
      }
    );
    my $gene_db = Seq::Build::GeneTrack->new($record);
    my ( $exon_sites_href, $flank_exon_sites_href, $tx_start_href ) =
      $gene_db->build_gene_db;

    # add information from annotation sites and start/stop sites into
    # master lists
    map { $flank_exon_sites{$_}++ } ( keys %$flank_exon_sites_href );
    map { $exon_sites{$_}++ }       ( keys %$exon_sites_href );
    for my $tx_start ( keys %$tx_start_href ) {
      for my $tx_stops ( @{ $tx_start_href->{$tx_start} } ) {
        push @{ $transcript_starts{$tx_start} }, $tx_stops;
      }
    }
  }

  # make another genomesized track to deal with the in/outside of genes
  # and ultimately write over those 0's and 1's to store the genome assembly
  # idx codes...
  my $assembly = Seq::Build::GenomeSizedTrackChar->new(
    {
      genome_length    => $self->genome_length,
      genome_index_dir => $self->genome_index_dir,
      genome_chrs      => $self->genome_chrs,
      name             => $self->genome_name,
      type             => 'genome',
      chr_len          => \%chr_len,
    }
  );

  # set genic/intergenic regions
  $assembly->set_gene_regions( \%transcript_starts );

  # use gene, snp tracks, and genic/intergenic regions to build coded genome
  $assembly->build_genome_idx( $self->genome_str_track, \%exon_sites,
    \%flank_exon_sites, \%snp_sites );
  $assembly->write_char_seq;
  $assembly->clear_char_seq;

  # write conservation scores
  if ( $self->genome_sized_tracks ) {
    foreach my $gst ( $self->all_genome_sized_tracks ) {
      my $score_track = Seq::Build::GenomeSizedTrackChar->new(
        {
          genome_length    => $self->genome_length,
          genome_index_dir => $self->genome_index_dir,
          genome_chrs      => $self->genome_chrs,
          chr_len          => \%chr_len,
          name             => $gst->name,
          type             => $gst->type,
          local_dir        => $gst->local_dir,
          local_files      => $gst->local_files,
        }
      );
      $score_track->build_score_idx;
      $score_track->write_char_seq;
      $score_track->clear_char_seq;
    }
  }
}

sub BUILDARGS {
  my $class = shift;
  my $href  = $_[0];
  if ( scalar @_ > 1 || reftype($href) ne "HASH" ) {
    confess "Error: $class expects hash reference.\n";
  }
  else {
    my %hash;
    for my $sparse_track ( @{ $href->{sparse_tracks} } ) {
      $sparse_track->{genome_name} = $href->{genome_name};
      if ( $sparse_track->{type} eq "gene" ) {
        push @{ $hash{gene_tracks} }, Seq::Config::SparseTrack->new($sparse_track);
      }
      elsif ( $sparse_track->{type} eq "snp" ) {
        push @{ $hash{snp_tracks} }, Seq::Config::SparseTrack->new($sparse_track);
      }
      else {
        croak "unrecognized sparse track type $sparse_track->{type}\n";
      }
    }
    for my $genome_str_track ( @{ $href->{genome_sized_tracks} } ) {
      $genome_str_track->{genome_chrs}      = $href->{genome_chrs};
      $genome_str_track->{genome_index_dir} = $href->{genome_index_dir};

      if ( $genome_str_track->{type} eq "genome" ) {
        $hash{genome_str_track} = Seq::Build::GenomeSizedTrackStr->new($genome_str_track);
      }
      elsif ( $genome_str_track->{type} eq "score" ) {
        push @{ $hash{genome_sized_tracks} },
          Seq::Config::GenomeSizedTrack->new($genome_str_track);

      }
      else {
        croak "unrecognized genome track type $genome_str_track->{type}\n";
      }
    }
    for my $attrib (
      qw( genome_name genome_description genome_chrs
      genome_raw_dir genome_index_dir )
      )
    {
      $hash{$attrib} //= $href->{$attrib} || "";
    }
    return $class->SUPER::BUILDARGS( \%hash );
  }
}

__PACKAGE__->meta->make_immutable;

1;
