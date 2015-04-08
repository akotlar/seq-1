use 5.10.0;
use strict;
use warnings;

package Seq::Build;
# ABSTRACT: A class for building a binary representation of a genome assembly
# VERSION

use Moose 2;

use Carp qw/ croak /;
use Cpanel::JSON::XS;
use MongoDB;
use namespace::autoclean;
use Path::Tiny;
use Scalar::Util qw/ reftype /;

use Seq::Build::SnpTrack;
use Seq::Build::GeneTrack;
use Seq::Build::TxTrack;
use Seq::Build::GenomeSizedTrackChar;
use Seq::Build::GenomeSizedTrackStr;
use Seq::BDBManager;
use Seq::MongoManager;


use DDP;

extends 'Seq::Assembly';
with 'Seq::Role::IO', 'MooX::Role::Logger';;

has genome_str_track => (
  is      => 'ro',
  isa     => 'Seq::Build::GenomeSizedTrackStr',
  handles => [ 'get_abs_pos', 'get_base', 'genome_length', ],
  lazy    => 1,
  builder => '_build_genome_str_track',
);

# has is_initialized => (
#   is      => 'ro',
#   isa     => 'Bool',
#   traits  => ['Bool'],
#   default => 0,
#   handles => { initalized => 'set', },
# );

sub _build_genome_str_track {
  my $self = shift;
  for my $gst ( $self->all_genome_sized_tracks ) {
    if ( $gst->type eq 'genome' ) {
      return Seq::Build::GenomeSizedTrackStr->new(
        {
          name             => $gst->name,
          type             => $gst->type,
          local_dir        => $gst->local_dir,
          local_files      => $gst->local_files,
          genome_chrs      => $gst->genome_chrs,
          genome_index_dir => $self->genome_index_dir,
        }
      );
    }
  }
}

# sub BUILD {
#   #before qw/ build_snp_sites build_gene_sites build_conserv_scores_index / => sub {
#   my $self = shift;
#   unless ( $self->is_initialized ) {
#     $self->initalized;
#   }
# }

sub build_assembly {
  my $self = shift;
  $self->build_genome_index;
  $self->build_conserv_scores_index;
}

sub save_bdb {
  my ( $self, $name ) = @_;
  my $dir = File::Spec->canonpath( $self->genome_index_dir );
  my $file = File::Spec->catfile( $dir, $name );

  path($dir)->mkpath unless -f $dir;

  return $file;
}

sub save_sites {
  my ( $self, $href, $name ) = @_;

  my $dir = File::Spec->canonpath( $self->genome_index_dir );
  my $file = File::Spec->catfile( $dir, $name );

  path($dir)->mkpath unless -f $dir;
  my $fh = $self->get_write_fh($file);

  return print { $fh } encode_json( $href );
}

sub load_sites {
  my ( $self, $name ) = @_;

  my $dir = File::Spec->canonpath( $self->genome_index_dir );
  my $file = File::Spec->catfile( $dir, $name );

  # do we find a file a non-zero file? Retrieve that data else undef.
  if ( -s $file ) {
    my $fh = $self->get_read_fh($file);
    local $/;
    my $json_txt = <$fh>;
    return decode_json($json_txt);
  }
  else {
    return;
  }
}

sub build_snp_sites {
  my $self = shift;
  # build snp tracks

  $self->_logger->info( 'in build_snp_sites' );

  my %snp_sites;
  if ( $self->snp_tracks ) {
    for my $snp_track ( $self->all_snp_tracks ) {

      # create a file name for loading / saving track data
      my $snp_track_file_name = join( '.', $snp_track->name, $snp_track->type, 'dat' );

      # create file for bdb
      my $snp_track_bdb = join( '.', $snp_track->name, $snp_track->type, 'db' );

      # is there evidence for having done this before?
      my $sites_aref = $self->load_sites($snp_track_file_name);

      # build the track if we didn't load anything
      unless ($sites_aref) {
        my $record = $snp_track->as_href;
        $record->{genome_track_str} = $self->genome_str_track;
        $record->{genome_index_dir} = $self->genome_index_dir;
        $record->{genome_name}      = $self->genome_name;
        # $record->{mongo_connection} = Seq::MongoManager->new(
        #   {
        #     default_database => $self->genome_name,
        #     client_options   => {
        #       host => $self->mongo_addr,
        #       port => $self->port,
        #     },
        #   }
        # );
        $record->{bdb_connection} =
          Seq::BDBManager->new( { filename => $self->save_bdb($snp_track_bdb), } );
        my $snp_db = Seq::Build::SnpTrack->new($record);
        $sites_aref = $snp_db->build_snp_db;

        # save the gene track data
        unless ( $self->save_sites( $sites_aref, $snp_track_file_name ) ) {
          croak "error saving snp sites for:  $snp_track_file_name\n";
        }
      }
      map { $snp_sites{$_}++ } @$sites_aref;
    }
  }
  $self->_logger->info( 'leaving build_snp_sites' );
  return \%snp_sites;
}

sub build_transcript_seq {
  my $self = shift;

  $self->_logger->info( 'in build_transcript_seq' );

  for my $gene_track ( $self->all_gene_tracks ) {

    # create a file name for loading / saving track data
    my $gene_track_file_name =
      join( '.', $gene_track->name, $gene_track->type, 'seq.dat' );

    # create file for bdb
    my $gene_track_seq_db = join( '.', $gene_track->name, $gene_track->type, 'seq.db' );

    # is there evidence for having done this before?
    my $done_sref = $self->load_sites($gene_track_file_name);

    unless ($done_sref) {
      my $record = $gene_track->as_href;
      $record->{genome_track_str} = $self->genome_str_track;
      $record->{genome_index_dir} = $self->genome_index_dir;
      $record->{genome_name}      = $self->genome_name;
      $record->{name}             = $gene_track->name . '_tx';
      # $record->{mongo_connection} = Seq::MongoManager->new(
      #   {
      #     default_database => $self->genome_name,
      #     client_options   => {
      #       host => $self->mongo_addr,
      #       port => $self->port,
      #     },
      #   }
      # );
      $record->{bdb_connection} =
        Seq::BDBManager->new( { filename => $self->save_bdb($gene_track_seq_db), } );
      my $gene_db = Seq::Build::TxTrack->new($record);
      $gene_db->insert_transcript_seq;
    }
    my $href = { 'done with gene sequence track' => 1 };

    # save the gene track data
    unless ( $self->save_sites( $href, $gene_track_file_name ) ) {
      croak "error saving snp sites for:  $gene_track_file_name\n";
    }
  }
  $self->_logger->info( 'leaving build_transcript_seq' );
}

sub build_gene_sites {
  my $self = shift;
  # build gene tracks - these are gene annotation tracks downloaded from UCSC
  # e.g., knownGene

  $self->_logger->info( 'in build_gene_sites' );

  my ( %flank_exon_sites, %exon_sites, %transcript_starts );
  for my $gene_track ( $self->all_gene_tracks ) {

    # create a file name for loading / saving track data
    my $gene_track_file_name = join( '.', $gene_track->name, $gene_track->type, 'dat' );

    # create a file for bdb
    my $gene_track_db = join( '.', $gene_track->name, $gene_track->type, 'db' );

    # try to load data
    my $sites_href = $self->load_sites($gene_track_file_name);

    # build the track if we didn't load anything
    unless ($sites_href) {
      my $record = $gene_track->as_href;
      $record->{genome_track_str} = $self->genome_str_track;
      $record->{genome_index_dir} = $self->genome_index_dir;
      $record->{genome_name}      = $self->genome_name;
      # $record->{mongo_connection} = Seq::MongoManager->new(
      #   {
      #     default_database => $self->genome_name,
      #     client_options   => {
      #       host => $self->mongo_addr,
      #       port => $self->port,
      #     },
      #   }
      # );
      $record->{bdb_connection} =
        Seq::BDBManager->new( { filename => $self->save_bdb($gene_track_db), } );
      my $gene_db = Seq::Build::GeneTrack->new($record);
      $sites_href = $gene_db->build_gene_db;

      # save the gene track data
      unless ( $self->save_sites( $sites_href, $gene_track_file_name ) ) {
        croak "error saving snp sites for:  $gene_track_file_name\n";
      }
    }

    # merge all gene track data into one master record
    map { $flank_exon_sites{$_}++ } ( keys %{ $sites_href->{flank_exon_sites} } );
    map { $exon_sites{$_}++ }       ( keys %{ $sites_href->{exon_sites} } );
    for my $tx_start ( keys %{ $sites_href->{transcript_start_sites} } ) {
      for my $tx_stops ( @{ $sites_href->{transcript_start_sites}{$tx_start} } ) {
        push @{ $transcript_starts{$tx_start} }, $tx_stops;
      }
    }
  }
  $self->_logger->info( 'leaving build_gene_sites' );
  return ( \%flank_exon_sites, \%exon_sites, \%transcript_starts );
}

sub build_conserv_scores_index {
  my $self = shift;

  $self->_logger->info( 'in build_conserv_scores_index' );

  # make chr_len hash for binary genome
  my %chr_len = map { $_ => $self->get_abs_pos( $_, 1 ) } ( $self->all_genome_chrs );

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
  $self->_logger->info( 'leaving build_conserv_scores_index' );
}

sub build_genome_index {
  my $self = shift;

  $self->_logger->info( 'in build_genome_index' );

  my $snp_sites = $self->build_snp_sites;
  my ( $flank_exon_sites, $exon_sites, $transcript_starts ) = $self->build_gene_sites;

  # make chromosome start offsets for binary genome
  my %chr_len = map { $_ => $self->get_abs_pos( $_, 1 ) } ( $self->all_genome_chrs );

  p %chr_len;

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
  $assembly->set_gene_regions($transcript_starts);

  # use gene, snp tracks, and genic/intergenic regions to build coded genome
  # the build_genome_idx now writes all needed files within the sub
  $assembly->build_genome_idx( $self->genome_str_track, $exon_sites,
    $flank_exon_sites, $snp_sites );
  $self->_logger->info( 'leaving build_genome_index' );
}

__PACKAGE__->meta->make_immutable;

1;
