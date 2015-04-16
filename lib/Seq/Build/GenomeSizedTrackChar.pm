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
use YAML::XS qw/ Dump /;

extends 'Seq::GenomeSizedTrackChar';
with 'Seq::Role::IO', 'Seq::Role::Genome', 'MooX::Role::Logger';

sub insert_char {
  my $self = shift;
  my ( $pos, $char ) = @_;
  state $seq_len = $self->genome_length;

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

# override '_build_char_seq' => sub {
#   my $self = shift;
#
#   # only need this for the score tracks since we're encoding the genome with C
#   if ( $self->type eq 'score' ) {
#     my $char_seq = pack( "C", '0' ) x $self->genome_length;
#     return \$char_seq;
#   }
#   else {
#     my $char_seq = '';
#     return \$char_seq;
#   }
# };

# the expecation of build_score_idx is the scores are in chromosomal order
#   i.e., the order in the YAML file and that positions are in order
sub old_build_score_idx {
  my $self = shift;

  $self->_logger->info( "begining to build encoded score for: " . $self->name );

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
    my ($chr, $rel_pos, $step, $abs_pos, $offset);
    while ( my $line = $in_fh->getline() ) {
      chomp $line;
      if ($line =~ m/\AfixedStep\schrom=([\w\d]+)\sstart=(\d+)\sstep=(\d)/) {
        $chr = $1;
        $rel_pos = $2;
        $step =$3; # not really needed
        $offset //= $chr_len_href->{$chr};
        $abs_pos = (defined $offset) ? $offset + $rel_pos : -9;
        $self->_logger->info( join " ", 'new range:', $chr, $rel_pos, $abs_pos );
      }
      else {
        next unless defined $offset; # skip sites that are in odd chrs
        my $char      = $self->score2char->($line);
        #say join "\t", $abs_pos, $line, sprintf("%d", $char);
        my $prev_char = substr ${ $self->char_seq }, $abs_pos, 1, pack( 'C', $char );
        $abs_pos += $step;
      }
    }
    close($in_fh);
  }
  print {$out_fh} ${ $self->char_seq };
  close($out_fh);

  # save chromosome offsets
  my $chr_offset_name = join( ".", $self->name, $self->type, 'yml' );
  my $chr_offset_file = File::Spec->catfile( $index_dir, $chr_offset_name );
  my $chr_offset_fh = $self->get_write_bin_fh($chr_offset_file);
  print {$chr_offset_fh} Dump( $self->chr_len );

  $self->_logger->info( "finished building encoded score for: " . $self->name );
}

__PACKAGE__->meta->make_immutable;

1;
