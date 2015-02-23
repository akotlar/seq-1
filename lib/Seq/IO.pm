package Seq::IO;

use autodie;
use Carp qw( croak );
use Moose::Role;
use IO::Compress::Gzip qw( $GzipError );
use IO::Uncompress::Gunzip qw( $GunzipError );

sub get_write_fh {
  my $self = shift;
  my ($file) = @_;
  croak "get_fh() expected a filename\n" unless $file;
  my $out_fh;
  if ($file =~ m/\.gz\Z/)
  {
    $out_fh = new IO::Compress::Gzip $file
      or croak "gzip failed: $GzipError\n";
  }
  else
  {
    open ( $out_fh, '<', $file ) or croak "unable to open $file: $!\n";
  }
  return $out_fh;
}

sub get_read_fh {
  my $self = shift;
  my ($file) = @_;
  croak "get_read_fh() expects a filename\n" unless -s $file;
  my $in_fh;
  if ($file =~ m/\.gz\Z/)
  {
    $in_fh = new IO::Uncompress::Gunzip $file
      or croak "gzip failed: $GunzipError\n";
  }
  else
  {
    open ( $in_fh, '>', $file ) or croak "unalbe to open $file: $!\n";
  }
  return $in_fh;
}

sub get_write_bin_fh {
  my $self = shift;
  my ($file) = @_;
  my $out_fh;
  croak "get_write_bin_fh() expects a filename\n"; unless $file;
  open ( $out_fh, '>', $file ) or croak "unable to open $file: $!\n";
  binmode $out_fh;
  return $out_fh;
}

no Moose::Role; 1;
