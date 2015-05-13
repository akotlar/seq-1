use 5.10.0;
use strict;
use warnings;

package Seq::Build;
# ABSTRACT: A class for building a binary representation of a genome assembly
# VERSION

use Moose 2;

use Carp qw/ croak /;
use File::Path qw/ make_path /;
use File::Spec;
use namespace::autoclean;
use Scalar::Util qw/ reftype /;
use YAML::XS qw/ Dump /;

use Seq::Build::SnpTrack;
use Seq::Build::GeneTrack;
use Seq::Build::TxTrack;
use Seq::Build::GenomeSizedTrackStr;
use Seq::KCManager;
#use Seq::MongoManager;

use DDP;

extends 'Seq::Assembly';
with 'Seq::Role::IO', 'MooX::Role::Logger';

has genome_str_track => (
  is      => 'ro',
  isa     => 'Seq::Build::GenomeSizedTrackStr',
  handles => [ 'get_abs_pos', 'get_base', 'genome_length', ],
  lazy    => 1,
  builder => '_build_genome_str_track',
);

has genome_hasher => (
  is      => 'ro',
  isa     => 'Str',
  default => 'genome_hasher',
);

has genome_scorer => (
  is      => 'ro',
  isa     => 'Str',
  default => 'genome_scorer',
);

has wanted_chr => (
  is => 'ro',
  isa => 'Maybe[Str]',
  default => undef,
);

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

sub _save_bdb {
  my ( $self, $name ) = @_;
  my $dir = File::Spec->canonpath( $self->genome_index_dir );
  my $file = File::Spec->catfile( $dir, $name );

  make_path($dir) unless -f $dir;

  return $file;
}

sub build_snp_sites {
  my $self = shift;

  $self->_logger->info('begining to build snp tracks');
  my %snp_sites;
  if ( $self->snp_tracks ) {
    for my $snp_track ( $self->all_snp_tracks ) {

      # create file for bdb
      my $snp_track_bdb = join( '.', $snp_track->name, $snp_track->type, 'kch' );

      # extract keys from snp_track for creation of Seq::Build::SnpTrack
      my $record = $snp_track->as_href;

      # add additional keys to the hashref for Seq::Build::SnpTrack
      $record->{genome_track_str} = $self->genome_str_track;
      $record->{genome_index_dir} = $self->genome_index_dir;
      $record->{genome_name}      = $self->genome_name;
      $record->{no_bdb_insert}    = $self->no_bdb_insert,
        $record->{bdb_connection} = Seq::KCManager->new(
        {
          filename      => $self->_save_bdb($snp_track_bdb),
          no_bdb_insert => $self->no_bdb_insert,
        }
        );
      my $snp_db = Seq::Build::SnpTrack->new($record);
      $snp_db->build_snp_db;
    }
  }
  $self->_logger->info('finished building snp tracks');
}

sub build_transcript_db {
  my $self = shift;

  $self->_logger->info('begining to build transcripts');

  for my $gene_track ( $self->all_gene_tracks ) {

    # create file for bdb
    my $gene_track_seq_db = join( '.', $gene_track->name, $gene_track->type, 'seq.kch' );

    # extract keys from snp_track for creation of Seq::Build::TxTrack
    my $record = $gene_track->as_href;

    my $db_file = $self->_save_bdb($gene_track_seq_db);
    $self->_logger->info('using db: ' . $db_file );

    # add additional keys to the hashref for Seq::Build::TxTrack
    $record->{genome_track_str} = $self->genome_str_track;
    $record->{genome_index_dir} = $self->genome_index_dir;
    $record->{genome_name}      = $self->genome_name;
    $record->{name}             = $gene_track->name;
    $record->{no_bdb_insert}    = $self->no_bdb_insert,
      $record->{bdb_connection} = Seq::KCManager->new(
      {
        filename      => $db_file,
        no_bdb_insert => $self->no_bdb_insert,
      }
      );

    my $gene_db = Seq::Build::TxTrack->new($record);
    $gene_db->insert_transcript_seq;
  }
  $self->_logger->info('finished building transcripts');
}

sub build_gene_sites {
  my $self = shift;
  # build gene tracks - these are gene annotation tracks downloaded from UCSC
  # e.g., knownGene

  $self->_logger->info('begining to build gene track');

  for my $gene_track ( $self->all_gene_tracks ) {

    # create a file for bdb
    my $gene_track_db = join( '.', $gene_track->name, $gene_track->type, 'kch' );

    # extract keys to the hashref for Seq::Build::GeneTrack
    my $record = $gene_track->as_href;

    # extra keys from snp_track for creation of Seq::Build::GeneTrack
    $record->{genome_track_str} = $self->genome_str_track;
    $record->{genome_index_dir} = $self->genome_index_dir;
    $record->{genome_name}      = $self->genome_name;
    $record->{bdb_connection}   = Seq::KCManager->new(
      {
        filename      => $self->_save_bdb($gene_track_db),
        no_bdb_insert => $self->no_bdb_insert,
      }
    );

    my $wanted_chr = $self->wanted_chr;
    my $gene_db = Seq::Build::GeneTrack->new($record);
    for my $chr ($self->all_genome_chrs) {

      # skip to the next chr if we specified a chr to build and this chr isn't
      #   the one we specified
      next unless $wanted_chr && $wanted_chr eq $chr;
      $self->_logger->info('building gene track for ' . $chr );
      $gene_db->build_gene_db_for_chr($chr);
    }
  }
  $self->_logger->info('finished building gene track');
}

sub build_conserv_scores_index {
  my $self = shift;

  $self->_logger->info('begining to build conservation scores');

  # make chr_len hash for binary genome
  my %chr_len = map { $_ => $self->get_abs_pos( $_, 1 ) } ( $self->all_genome_chrs );

  # prepare index dir
  my $index_dir = File::Spec->canonpath( $self->genome_index_dir );
  make_path($index_dir) unless -f $index_dir;

  # write conservation scores
  if ( $self->genome_sized_tracks ) {
    foreach my $gst ( $self->all_genome_sized_tracks ) {
      next unless $gst->type eq 'score';

      # make chromosome start offsets for binary genome
      my %chr_len = map { $_ => $self->get_abs_pos( $_, 1 ) } ( $self->all_genome_chrs );

      # write chromosome offsets
      my $chr_offset_name = join( ".", $gst->name, $gst->type, 'yml' );
      my $chr_offset_file = File::Spec->catfile( $index_dir, $chr_offset_name );
      my $chr_offset_fh = $self->get_write_fh($chr_offset_file);
      print {$chr_offset_fh} Dump( \%chr_len );

      # set idx file
      my $idx_name = join( ".", $gst->name, $gst->type, 'idx' );
      my $idx_file = File::Spec->catfile( $index_dir, $idx_name );

      # find file
      my $local_dir = File::Spec->canonpath( $gst->local_dir );
      my $local_file = File::Spec->catfile( $local_dir, $gst->first_local_file );

      croak "expected file to be a wigFix file" unless $local_file =~ m/wigFix/;

      # set path to binary encoder
      my $genome_scorer = File::Spec->canonpath( $self->genome_scorer );
      my $cmd = join " ", $genome_scorer, $self->genome_length, $chr_offset_file,
        $local_file, $gst->score_max, $gst->score_min, $gst->score_R, $idx_file;

      $self->_logger->info("running command: $cmd");

      my $exit_code = system $cmd;

      croak "error encoding genome with $genome_scorer: $exit_code" if $exit_code;
      croak "error making encoded genome - did not find $idx_file " unless -f $idx_file;
    }
  }
  $self->_logger->info('finished building conservation scores');
}

sub build_genome_index {
  my $self = shift;

  # build needed tracks, which write ranges for snp and gene sites
  $self->build_snp_sites;
  $self->build_gene_sites;

  # prepare index dir
  my $index_dir = File::Spec->canonpath( $self->genome_index_dir );
  make_path($index_dir) unless -f $index_dir;

  # prepare idx file and file list needed to make indexed genome
  my $idx_name       = join( ".", $self->genome_name, 'genome', 'idx' );
  my $file_list_name = join( ".", $self->genome_name, 'genome', 'list' );
  my $idx_file       = File::Spec->catfile( $index_dir, $idx_name );
  my $file_list_file = File::Spec->catfile( $index_dir, $file_list_name );
  my $file_list_fh   = $self->get_write_fh($file_list_file);

  my @file_list_files;

  $self->_logger->info('writing genome file list');

  # cycle through all snp and gene tracks and check that we have a file for them
  # in the index dir; write a file with all of them plus the sequence file
  # and that off to genome_hasher and check that something was

  # input files
  my $genome_str_name = join ".", $self->genome_name, 'genome', 'str', 'dat';
  my $genome_str_file = File::Spec->catfile( $index_dir, $genome_str_name );

  if ( $self->snp_tracks ) {
    for my $snp_track ( $self->all_snp_tracks ) {
      my $snp_name = join( ".", $snp_track->name, 'snp', 'dat' );
      push @file_list_files, File::Spec->catfile( $index_dir, $snp_name );
    }
  }

  for my $gene_track ( $self->all_gene_tracks ) {
    my $gan_name         = join( ".", $gene_track->name, 'gan',         'dat' );
    my $exon_name        = join( ".", $gene_track->name, 'exon',        'dat' );
    my $gene_region_name = join( ".", $gene_track->name, 'gene_region', 'dat' );
    push @file_list_files, File::Spec->catfile( $index_dir, $gan_name );
    push @file_list_files, File::Spec->catfile( $index_dir, $exon_name );
    push @file_list_files, File::Spec->catfile( $index_dir, $gene_region_name );
  }
  say {$file_list_fh} join "\n", @file_list_files;

  # get abs path to genome_hasher
  my $genome_hasher = File::Spec->canonpath( $self->genome_hasher );

  my $cmd = qq{ $genome_hasher $genome_str_file $file_list_file $idx_file };

  $self->_logger->info("running command: $cmd");

  my $exit_code = system $cmd;

  croak "error encoding genome with $genome_hasher: $exit_code" if $exit_code;
  croak "error making encoded genome - did not find $idx_file " unless -f $idx_file;

  # make chromosome start offsets for binary genome
  my %chr_len = map { $_ => $self->get_abs_pos( $_, 1 ) } ( $self->all_genome_chrs );

  # write chromosome offsets
  my $chr_offset_name = join( ".", $self->genome_name, 'genome', 'yml' );
  my $chr_offset_file = File::Spec->catfile( $index_dir, $chr_offset_name );
  my $chr_offset_fh = $self->get_write_fh($chr_offset_file);

  print {$chr_offset_fh} Dump( \%chr_len );

  $self->_logger->info('finished building genome index');
}

__PACKAGE__->meta->make_immutable;

1;
