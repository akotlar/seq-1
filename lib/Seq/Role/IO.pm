use 5.10.0;
use strict;
use warnings;

package Seq::Role::IO;

our $VERSION = '0.001';

# ABSTRACT: A moose role for all of our file handle needs
# VERSION

=head1 DESCRIPTION

  @role Seq::Role::IO
  #TODO: Check description

  @example with 'Seq::Role::IO'

Used in:
=for :list
* Seq/Build/GeneTrack.pm
* Seq/Build/GenomeSizedTrackStr.pm
* Seq/Build/SnpTrack.pm
* Seq/Build/TxTrack.pm
* Seq/Build.pm
* Seq/Fetch/Sql.pm
* Seq/GenomeSizedTrackChar.pm
* Seq/KCManager.pm
* Seq/Role/ConfigFromFile.pm
* Seq

Extended by: None

=cut

use Moose::Role;

use Carp qw/ confess /;
use IO::File;
use IO::Compress::Gzip qw/ $GzipError /;
use IO::Uncompress::Gunzip qw/ $GunzipError /;
use Path::Tiny;
use File::Slurper;
use Scalar::Util qw/ reftype /;

# tried various ways of assigning this to an attrib, with the intention that
# one could change the taint checking characters allowed but this is the simpliest
# one that worked; wanted it precompiled to improve the speed of checking
my $taint_check_regex = qr{\A([\,\.\-\=\:\/\t\s\w\d]+)\z};

sub get_read_fh {
  my ( $class, $file ) = @_;

  my $fh;
  my $reftype = reftype $file;

  # TODO: should explicitly check it's a Path::Tiny object
  if ( defined $reftype ) {
    $file = $file->absolute->stringify;
    if ( !-f $file ) {
      confess sprintf( "ERROR: file does not exist for reading: %s", $file );
    }
  }

  if ( $file =~ m/\.gz\Z/ ) {
    $fh = IO::Uncompress::Gunzip->new($file)
      || confess "\nError: gzip failed: $GunzipError\n";
  }
  else {
    $fh = IO::File->new( $file, 'r' )
      || confess "\nError: unable to open file ($file) for reading: $!\n";
  }
  return $fh;
}

sub get_file_lines {
  my ( $self, $filePath ) = @_;
  if ( !-f $filePath ) {
    confess sprintf( "ERROR: file does not exist for reading: %s", $filePath );
  }
  return path($filePath)->lines; #returns array
}

#another version, seems slower in practice
#if using this no need to chomp each individual line
sub slurp_file_lines {
  my ( $self, $filePath ) = @_;
  if ( !-f $filePath ) {
    confess sprintf( "ERROR: file does not exist for reading: %s", $filePath );
  }
  return File::Slurper::read_lines( $filePath, 'utf-8', { chomp => 1 } )
    ; #returns array
}

sub get_write_fh {
  my ( $class, $file ) = @_;

  confess "\nError: get_fh() expected a filename\n" unless $file;

  my $fh;
  if ( $file =~ m/\.gz\Z/ ) {
    $fh = IO::Compress::Gzip->new($file)
      || confess "gzip failed: $GzipError\n";
  }
  else {
    $fh = IO::File->new( $file, 'w' )
      || confess "\nError: unable to open file ($file) for writing: $!\n";
  }
  return $fh;
}

sub get_write_bin_fh {
  my ( $class, $file ) = @_;

  confess "\nError: get_write_bin_fh() expects a filename\n" unless $file;

  my $fh = IO::File->new( $file, 'w' )
    || confess "\nError: unable to open file ($file) for writing: $!\n";
  binmode $fh;
  return $fh;
}

sub clean_line {
  my ( $class, $line ) = @_;

  if ( $line =~ m/$taint_check_regex/xm ) {
    return $1;
  }
  return;
}

no Moose::Role;

1;
