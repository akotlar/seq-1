use 5.10.0;
use strict;
use warnings;

package Seq::Build;
# ABSTRACT: A class for building a binary representation of a genome assembly
# VERSION
# TODO: make the build class extend the assembly class

use Moose 2;

use Carp qw/ croak /;
use MongoDB;
use namespace::autoclean;
use Scalar::Util qw/ reftype /;

use Seq::Build::SnpTrack;
use Seq::Build::GeneTrack;
use Seq::Build::GenomeSizedTrackChar;
use Seq::Build::GenomeSizedTrackStr;
use Seq::MongoManager;

extends 'Seq::Assembly';
with 'Seq::Role::IO';

has genome_str_track => (
  is      => 'ro',
  isa     => 'Seq::Build::GenomeSizedTrackStr',
  handles => [ 'get_abs_pos', 'get_base', 'build_genome', 'genome_length', ],
  lazy    => 1,
  builder => '_build_genome_str_track',
);

sub _build_genome_str_track {
  my $self = shift;
  for my $gst ( $self->all_genome_sized_tracks ) {
    if ( $gst->type eq 'genome' ) {
      return Seq::Build::GenomeSizedTrackStr->new(
        {
          name        => $gst->name,
          type        => $gst->type,
          local_dir   => $gst->local_dir,
          local_files => $gst->local_files,
          genome_chrs => $gst->genome_chrs,
        }
      );
    }
  }
}

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
      $record->{genome_track_str} = $self->genome_str_track;
      $record->{genome_index_dir} = $self->genome_index_dir;
      $record->{genome_name}      = $self->genome_name;
      $record->{mongo_connection} = Seq::MongoManager->new(
        {
          default_database => $self->genome_name,
          client_options   => {
            host => $self->mongo_addr,
            port => $self->port,
          },
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
        client_options   => {
          host => $self->mongo_addr,
          port => $self->port,
        },
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
      next unless $gst->type eq 'score';
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

__PACKAGE__->meta->make_immutable;

1;
