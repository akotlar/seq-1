use 5.10.0;
use strict;
use warnings;

package Seq::Build::GenomeSizedTrackChar;

# ABSTRACT: Builds encoded binary representation of the genome
# VERSION

use Moose 2;

use Carp qw/ confess /;
use File::Path;
use File::Spec;
use namespace::autoclean;
use Scalar::Util qw/ reftype /;
use YAML::XS qw/ Dump /;

extends 'Seq::GenomeSizedTrackChar';
with 'Seq::Role::IO', 'Seq::Role::Genome';

sub insert_char {
  my $self = shift;
  my ( $pos, $char ) = @_;
  my $seq_len = $self->genome_length;

  confess "insert_char expects insert value and absolute position"
    unless defined $char and defined $pos;
  confess "insert_char expects insert value between 0 and 255"
    unless ( $char >= 0 and $char <= 255 );
  confess "insert_char expects pos value between 0 and $seq_len, got $pos"
    unless ( $pos >= 0 and $pos < $seq_len );

  # inserted character is a byproduct of a successful substr event
  my $inserted_char =
    substr( ${ $self->char_seq }, $pos, 1, pack( 'C', $char ) );

  return $inserted_char;
}

sub insert_score {
  my $self = shift;
  my ( $pos, $score ) = @_;
  my $seq_len = $self->genome_length;

  confess "insert_score expects pos value between 0 and $seq_len, got $pos"
    unless ( $pos >= 0 and $pos < $seq_len );
  confess "insert_score expects score2char() to be a coderef"
    unless $self->meta->find_method_by_name('score2char')
    and reftype( $self->score2char ) eq 'CODE';

  my $char_score = $self->score2char->($score);
  my $inserted_char = $self->insert_char( $pos, $char_score );
  return $inserted_char;
}

override '_build_char_seq' => sub {
  my $self     = shift;
  my $char_seq = "";
  for ( my $pos = 0; $pos < $self->genome_length; $pos++ ) {
    $char_seq .= pack( 'C', 0 );
  }
  return \$char_seq;
};

sub write_char_seq {

  # write idx file
  my $self        = shift;
  my $file        = join( ".", $self->name, $self->type, 'idx' );
  my $index_dir   = File::Spec->canonpath( $self->genome_index_dir );
  my $target_file = File::Spec->catfile( $index_dir, $file );
  my $fh          = $self->get_write_bin_fh($target_file);
  print {$fh} ${ $self->char_seq };
  close $fh;

  # write char_len for each track - this is repetitive but, I think, will make
  # things simplier than only doing it for one track
  $file        = join( ".", $self->name, $self->type, 'yml' );
  $index_dir   = File::Spec->canonpath( $self->genome_index_dir );
  $target_file = File::Spec->catfile( $index_dir, $file );
  $fh          = $self->get_write_bin_fh($target_file);
  print {$fh} Dump( $self->chr_len );
  close $fh;
}

sub build_score_idx {
  my $self = shift;

  my $chr_len_href     = $self->chr_len;
  my $local_files_aref = $self->local_files;
  my $local_dir        = File::Spec->canonpath( $self->local_dir );

  for my $i ( 0 .. $#{$local_files_aref} ) {
    my $file       = $local_files_aref->[$i];
    my $local_file = File::Spec->catfile( $local_dir, $file );
    my $fh         = $self->get_read_fh($local_file);
    my ( $last_pos, $last_chr, $abs_pos ) = ( 0, 0, 0 );
    while ( my $line = $fh->getline() ) {
      chomp $line;
      my ( $chr, $pos, $score ) = split( "\t", $line );
      if ($chr eq $last_chr) {
        $abs_pos += $pos - $last_pos;
        $last_pos = $pos;
      }
      else {
        my $offset //= $chr_len_href->{$chr};
        if (defined $offset) {
          $abs_pos = $offset + $pos;
        }
        else {
          confess "unrecognized chr: $chr in line: $line of $file";
        }
      }
      $self->insert_score( $abs_pos, $score );
      $last_chr = $chr;
    }
  }
}

sub build_genome_idx {
  my ( $self, $genome_str, $exon_href, $flank_exon_href, $snp_href ) = @_;

  confess "expected genome object to be able to get_abs_pos() and get_base()"
    unless ( $genome_str->meta->has_method('get_abs_pos')
    and $genome_str->meta->has_method('get_base') );

  confess "build_idx() expected a 3 hashes - exon, flanking exon, and snp sites"
    unless reftype($exon_href) eq "HASH"
    and reftype($flank_exon_href) eq "HASH"
    and reftype($snp_href) eq "HASH";

  for ( my $pos = 0; $pos < $self->genome_length; $pos++ ) {

    # all absolute bases are zero-indexed
    my $this_base = $genome_str->get_base( $pos, 1 );
    my ( $in_gan, $in_gene, $in_exon, $in_snp ) = ( 0, 0, 0, 0 );

    # $in_gan -> means is this site annotated in the MongoDb gene track
    # e.g., 5'UTR, Coding, intronic splice site donor, etc.
    $in_gan = 1
      if exists $exon_href->{$pos} || exists $flank_exon_href->{$pos};
    $in_gene = $self->get_base($pos);
    $in_exon = 1 if exists $exon_href->{$pos};
    $in_snp  = 1 if exists $snp_href->{$pos};

    my $site_code =
      $self->get_idx_code( $this_base, $in_gan, $in_gene, $in_exon, $in_snp );
    if ( defined $site_code ) {
      $self->insert_char( $pos, $site_code );
    }
    else {
      confess "fatal error at base: $pos ($this_base)\n"
        . "in_gan: $in_gan, in_gene: $in_gene, in_exon: $in_exon, in_snp: $in_snp";
    }
  }
}

sub set_gene_regions {
  my ( $self, $tx_starts_href ) = @_;

  # note: - tx = transcript
  #       - the $tx_starts_href is a hash with keys that are
  #         tx start sites and values are arrays of end values

  confess "set_gene_regions() can only be done on a genome type, not "
    . $self->type . "\n"
    unless $self->type eq "genome";
  confess "set_gene_regions() requires an array reference of transcript coordinates\n"
    unless reftype($tx_starts_href) eq "HASH";

  my @sorted_tx_starts = sort { $a <=> $b } keys %$tx_starts_href;

  # variables
  my ( $i, $tx_start, $tx_stop ) = ( 0, 0, 0 );

  # pick the 1st start site
  $tx_start = $sorted_tx_starts[$i];
  $i++;
  my @tx_stops = sort { $b <=> $a } @{ $tx_starts_href->{$tx_start} };
  $tx_stop = shift @tx_stops;

  # recall the char string will be initialized to Zero's already so we only
  # need to consider when we are in a gene region
  for ( my $pos = 0; $pos < $self->genome_length; $pos++ ) {
    if ( $pos > ( $tx_start - 1 ) && $pos < ( $tx_stop - 1 ) ) {
      $self->insert_char( $pos, '1' );
    }
    elsif ( $pos == ( $tx_stop - 1 ) ) {

      # end of coding portion of genome?
      if ( $i < scalar @sorted_tx_starts ) {
        $self->insert_char( $pos, '1' );

        # pick a new tx start and stop with a stop beyond the present position
        while ( ( $tx_stop - 1 ) <= $pos ) {
          $tx_start = $sorted_tx_starts[$i];
          $i++;
          my @new_tx_stops =
            sort { $b <=> $a } @{ $tx_starts_href->{$tx_start} };
          $tx_stop = shift @new_tx_stops;
        }
      }
    }
  }
}

__PACKAGE__->meta->make_immutable;

1;
