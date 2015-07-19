use 5.10.0;
use strict;
use warnings;

package Seq::Build;
# ABSTRACT: A class for building all files associated with a genome assembly
# VERSION

=head1 DESCRIPTION

  @class Seq::Build
  #TODO: Check description
  Build the annotation databases, as prescribed by the genome assembly.

  @example

Uses:
=for :list
* @class Seq::Build::SnpTrack
* @class Seq::Build::GeneTrack
* @class Seq::Build::TxTrack
* @class Seq::Build::GenomeSizedTrackStr
* @class Seq::KCManager
* @role Seq::Role::IO

Used in:
=for :list
* /bin/build_genome_assembly.pl

Extended in: None

=cut

use Moose 2;
use MooseX::Types::Path::Tiny qw/ AbsFile /

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
  isa     => AbsFile,
  default => './genome_hasher',
);

has genome_scorer => (
  is      => 'ro',
  isa     => AbsFile,
  default => './genome_scorer',
);

has genome_cadd => (
  is => 'ro',
  isa => AbsPath,
  default => './genome_cadd'
);

has wanted_chr => (
  is      => 'ro',
  isa     => 'Maybe[Str]',
  default => undef,
);

sub BUILD {
  my $self = shift;
  $self->_logger->info( "loading genome of size " . $self->genome_length );
  $self->_logger->info( "genome_hasher: " . $self->genome_hasher );
  $self->_logger->info( "genome_scoreer: " . $self->genome_scorer );
  $self->_logger->info( "wanted_chr: " . $self->wanted_chr );
}

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

sub build_transcript_db {
  my $self = shift;

  $self->_logger->info('begining to build transcripts');

  for my $gene_track ( $self->all_gene_tracks ) {

    my $msg = sprintf("begining gene tx db, '%s'", $gene_track->name);
    $self->_logger->info( $msg ) if $self->debug;

    # extract keys from snp_track for creation of Seq::Build::TxTrack
    my $record = $gene_track->as_href;

    # add additional keys to the hashref for Seq::Build::TxTrack
    $record->{genome_track_str} = $self->genome_str_track;
    my $gene_db = Seq::Build::GeneTrack->new($record);
    $gene_db->build_tx_db_for_genome;

    $msg = sprintf("finished gene tx db, '%s'", $gene_track->name);
    $self->_logger->info( $msg ) if $self->debug;
  }
  $self->_logger->info('finished building transcripts');
}

sub build_snp_sites {
  my $self = shift;

  $self->_logger->info('begining to build snp tracks');
  my $wanted_chr = $self->wanted_chr;

  for my $snp_track ( $self->all_snp_tracks ) {

    # extract keys from snp_track for creation of Seq::Build::SnpTrack
    my $record = $snp_track->as_href;

    for my $chr ( $self->all_genome_chrs ) {

      # skip to the next chr if we specified a chr to build
      # and this chr isn't the one we specified
      if ( defined $wanted_chr ) {
        next unless $wanted_chr eq $chr;
      }

      my $msg = sprintf("begining snp db, '%s', for chrom '%s'", $snp_track->name, $chr);
      $self->_logger->info( $msg ) if $self->debug;

      # Seq::Build::SnpTrack needs the string genome
      $record->{genome_track_str} = $self->genome_str_track;
      my $snp_db = Seq::Build::SnpTrack->new($record);
      $snp_db->build_snp_db($chr);

      $msg = sprintf("finished snp db, '%s', for chrom '%s'", $snp_track->name, $chr);
      $self->_logger->info( $msg ) if $self->debug;
    }
  }
  $self->_logger->info('finished building snp tracks');
}

sub build_gene_sites {
  my ( $self, $chr ) = @_;

  $self->_logger->info('begining to build gene track');

  my $wanted_chr = $self->wanted_chr;

  for my $gene_track ( $self->all_gene_tracks ) {

    # extract keys to the hashref for Seq::Build::GeneTrack
    my $record = $gene_track->as_href;

    for my $chr ( $self->all_genome_chrs ) {

      # skip to the next chr if we specified a chr to build and this chr isn't
      #   the one we specified
      if ( defined $wanted_chr ) {
        next unless $wanted_chr eq $chr;
      }

      my $msg = sprintf("begining gene db, '%s', for chrom '%s'", $gene_track->name, $chr);
      $self->_logger->info( $msg ) if $self->debug;

      # Seq::Build::GeneTrack needs the string genome
      $record->{genome_track_str} = $self->genome_str_track;
      my $gene_db = Seq::Build::GeneTrack->new($record);
      $gene_db->build_gene_db_for_chr($chr);

      $msg = sprintf("finished gene db, '%s', for chrom '%s'", $gene_track->name, $chr);
      $self->_logger->info( $msg ) if $self->debug;
    }
  }
  $self->_logger->info('finished building gene track');
}

sub build_conserv_scores_index {
  my $self = shift;

  # TODO: update to use Config::GenomeSizedTrack

  $self->_logger->info('begining to build conservation scores');

  # make chr_len hash for binary genome
  my %chr_len = map { $_ => $self->get_abs_pos( $_, 1 ) } ( $self->all_genome_chrs );

  # prepare index dir
  my $index_dir = $self->genome_index_dir->absolute->stringify;
  $self->genome_index->mk_path unless -f $index_dir;

  # write conservation scores
  if ( $self->genome_sized_tracks ) {
    foreach my $gst ( $self->all_genome_sized_tracks ) {

    if ( $gst->type eq 'score' ) {

      # write chromosome offsets
      my $chr_offset_file = $gst->genome_offset_file;
      my $chr_offset_fh   = $self->get_write_fh($chr_offset_file);
      print {$chr_offset_fh} Dump( \%chr_len );

      # local file
      my @local_files = $gst->all_local_files;
      unless (scalar @local_files == 1 && $local_files[0] =~ m/wigFix/) {
        my $msg = sprintf("expected 1 local file to build but found %d: %s",
          scalar @local_files, join ("\t", @local_files) );
        $self->_logger->error($msg);
        croak $msg;
      }

      # build cmd for external encoder
      my $cmd = join " ", $self->genome_scorer, $self->genome_length, $chr_offset_file,
        $local_files[0], $gst->score_max, $gst->score_min, $gst->score_R,
        $gst->genome_bin_file;

      $self->_logger->info("running command: $cmd");

      my $exit_code = system $cmd;

      if ( $exit_code ) {
        my $msg = sprintf("error encoding genome with %s: %d",
          $self->genome_scorer, $exit_code);
        $self->_logger->error($msg)
        croak $msg;
      }
      elsif (!-f $self->genome_bin_file) {
        my $msg = sprintf("ERROR: did not find expected output '%s'",
          $gst->genome_bin_file);
        $self->_logger->error($msg)
        croak $msg;
      }
    }
    elsif ( $gst->track eq 'cadd' ) {

      # write chromosome offsets
      my $chr_offset_file = $gst->genome_offset_file;
      my $chr_offset_fh   = $self->get_write_fh($chr_offset_file);
      print {$chr_offset_fh} Dump( \%chr_len );

      # local file
      my @local_files = $gst->all_local_files;
      unless (scalar @local_files == 1 && $local_files[0] =~ m/cadd/) {
        my $msg = sprintf("expected 1 local file to build but found %d: %s",
          scalar @local_files, join ("\t", @local_files) );
        $self->_logger->error($msg);
        croak $msg;
      }

      # build cmd for external encoder
      my $cmd = join " ", $self->genome_cadd, $self->genome_length, $chr_offset_file,
        $local_files[0], $gst->score_max, $gst->score_min, $gst->score_R,
        $gst->genome_bin_file;

      $self->_logger->info("running command: $cmd");

      my $exit_code = system $cmd;

      if ( $exit_code ) {
        my $msg = sprintf("error encoding genome with %s: %d",
          $self->genome_cadd, $exit_code);
        $self->_logger->error($msg)
        croak $msg;
      }
      elsif (!-f $self->genome_bin_file) {
        my $msg = sprintf("ERROR: did not find expected output '%s'",
          $gst->genome_bin_file);
        $self->_logger->error($msg)
        croak $msg;
      }
    }
  }
  $self->_logger->info('finished building conservation scores');
}

sub build_genome_index {
  my $self = shift;

  $self->_logger->info('begining to build indexed genome');

  # build needed tracks, which write ranges for snp and gene sites
  #   NOTE: if the tracks are built then nothing will be done unless force is
  #         true in which case the tracks will be rebuilt
  $self->build_snp_sites;
  $self->build_gene_sites;
  $self->build_transcript_db;

  # prepare index dir
  my $index_dir = $self->genome_index_dir->absolute->stringify;
  $self->genome_index->mk_path unless -f $index_dir;

  # get genome configuration object
  #   NOTE: needed for genome_offset_file(), genome_bin_file(), and
  #         genome_str_file() methods
  my $genome_build_obj;
  foreach my $gst ( $self->all_genome_sized_tracks ) {
    if ( $gst->type eq 'genome' ) {
      $genome_build_obj = $gst;
    }
  }

  # make chromosome start offsets for binary genome
  my %chr_len = map { $_ => $self->get_abs_pos( $_, 1 ) } ( $self->all_genome_chrs );

  # write chromosome offsets
  my $chr_offset_file = $genome_build_obj->genome_offset_file;
  my $chr_offset_fh = $self->get_write_fh($chr_offset_file);
  print {$chr_offset_fh} Dump( \%chr_len );

  # prepare file that will list all regions to be added
  my $file_list_name   = join( ".", $self->genome_name, 'genome', 'list' );
  my $region_list_file = File::Spec->catfile( $index_dir, $file_list_name );
  my $file_list_fh     = $self->get_write_fh($region_list_file);

  my @region_files;

  $self->_logger->info('writing genome file list');

  # input files for each chr
  # NOTE: cycle through all snp and gene tracks and combine into one file list
  #       for genome_hasher
  for my $chr ( $self->all_genome_chrs ) {

    # snp sites
    for my $snp_track ( $self->all_snp_tracks ) {
      push @region_files, $self->get_dat_file( $chr, $snp_track->type );
    }

    # gene annotation and exon positions
    for my $gene_track ( $self->all_gene_tracks ) {
      push @region_files, $self->get_dat_file( $chr, 'gan' );
      push @region_files, $self->get_dat_file( $chr, 'exon' );
    }
  }

  # gather gene region site files
  for my $gene_track ( $self->all_gene_tracks ) {
    push @region_files, $self->get_dat_file( 'genome', 'tx' );
  }

  # check files in region file exist for genome_hasher
  for my $file ( @region_files ) {
    if ( ! -f $file ) {
      my $msg = sprintf("ERROR: expected file: '%s' not found", $file);
      $self->_logger->error($msg);
      say $msg;
    }
  }

  # write file locations
  say {$file_list_fh} join "\n", @region_files;

  my $cmd = join " ", $self->genome_hasher, $genome_build_obj->genome_str_file,
    $region_list_file, $genome_build_obj->genome_bin_file;

  $self->_logger->info("running command: $cmd");

  my $exit_code = system $cmd;

  if ( $exit_code ) {
    my $msg = sprintf("error encoding genome with %s: %d",
      $self->genome_cadd, $exit_code);
    $self->_logger->error($msg)
    croak $msg;
  }
  elsif (!-f $self->genome_bin_file) {
    my $msg = sprintf("ERROR: did not find expected output '%s'",
      $gst->genome_bin_file);
    $self->_logger->error($msg)
    croak $msg;
  }

  $self->_logger->info('finished building genome index');
}

__PACKAGE__->meta->make_immutable;

1;
