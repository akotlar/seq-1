use 5.10.0;
use strict;
use warnings;

package Seq::Build::GenomeSizedTrackChar;

# ABSTRACT: Builds encoded binary representation of the genome
# VERSION

use Moose 2;

use Carp qw/ confess /;
use File::Path qw/ make_path /;
use File::Spec;
use namespace::autoclean;
use Scalar::Util qw/ reftype /;

extends 'Seq::GenomeSizedTrackChar';
with 'Seq::Role::IO', 'Seq::Role::Genome', 'MooX::Role::Logger';

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

  # substr returns the substituted part of the string
  my $prev_char =
    substr( ${ $self->char_seq }, $pos, 1, pack( 'C', $char ) );

  return $prev_char;
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

  my $char = $self->score2char->($score);

  # substr returns the substituted part of the string
  my $prev_char =
    substr( ${ $self->char_seq }, $pos, 1, pack( 'C', $char ) );

  return $prev_char;
}

override '_build_char_seq' => sub {
  my $self = shift;

  # only need this for the score tracks since we're encoding the genome with C
  if ( $self->type eq 'score' ) {
    my $char_seq = pack( "C", '0' ) x $self->genome_length;
    return \$char_seq;
  }
  else {
    my $char_seq = '';
    return \$char_seq;
  }
};

# the expecation of build_score_idx is the scores are in chromosomal order
#   i.e., the order in the YAML file and that positions are in order
sub build_score_idx {
  my $self = shift;

  $self->_logger->info('in build_score_idx');

  my $chr_len_href     = $self->chr_len;
  my $local_files_aref = $self->local_files;
  my $local_dir        = File::Spec->canonpath( $self->local_dir );

  # prepare file for output
  my $file        = join( ".", $self->name, $self->type, 'idx' );
  my $index_dir   = File::Spec->canonpath( $self->genome_index_dir );
  my $target_file = File::Spec->catfile( $index_dir, $file );
  my $out_fh      = $self->get_write_bin_fh($target_file);

  my $char_zero = pack( 'C', '0' );
  my @tmp;

  for my $i ( 0 .. $#{$local_files_aref} ) {
    my $file       = $local_files_aref->[$i];
    my $local_file = File::Spec->catfile( $local_dir, $file );
    my $in_fh      = $self->get_read_fh($local_file);
    my ( $last_pos, $last_chr, $abs_pos, $last_abs_pos ) = ( 0, 0, 0, 0 );
    while ( my $line = $in_fh->getline() ) {
      chomp $line;
      my ( $chr, $pos, $score ) = split( "\t", $line );
      if ( $chr eq $last_chr ) {
        $abs_pos += $pos - $last_pos;
        $last_pos = $pos;
      }
      else {
        my $offset //= $chr_len_href->{$chr};
        if ( defined $offset ) {
          $abs_pos  = $offset + $pos;
          $last_pos = $pos;
          $last_chr = $chr;
        }
        else {
          confess "unrecognized chr: $chr in line: $line of $file";
        }
      }
      my $diff = $abs_pos - ( $last_abs_pos + 1 );

      unless ( $last_abs_pos + 1 == $abs_pos ) {
        for ( my $i = $last_abs_pos + 1; $i < $abs_pos; $i++ ) {
          print {$out_fh} $char_zero;
        }
      }
      print {$out_fh} pack( 'C', $self->score2char->($score) );

      # $self->insert_score( $abs_pos, $score );
      $last_abs_pos = $abs_pos;
      $last_chr     = $chr;
    }
    for ( my $i = $abs_pos; $i < $self->genome_length; $i++ ) {
      print {$out_fh} $char_zero;
    }
    close($in_fh);
  }
  close($out_fh);
  $self->_logger->info('leaving build_score_idx');
}

__PACKAGE__->meta->make_immutable;

1;
