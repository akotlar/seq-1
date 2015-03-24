package Seq::Role::IO;

use 5.10.0;
use Carp qw( confess croak );
use Moose::Role;
use IO::File;
use IO::Compress::Gzip qw( $GzipError );
use IO::Uncompress::Gunzip qw( $GunzipError );

sub get_write_fh {
  my ( $self, $file ) = @_;
  croak "\nError: get_fh() expected a filename\n" unless $file;
  my $fh;
  if ( $file =~ m/\.gz\Z/ ) {
    $fh = new IO::Compress::Gzip $file
      || croak "gzip failed: $GzipError\n";
  }
  else {
    $fh = IO::File->new( $file, 'w' )
      || confess "\nError: unable to open file ($file) for writing: $!\n";
  }
  return $fh;
}

sub get_read_fh {
  my ( $self, $file ) = @_;

  croak "\nError: get_read_fh() expects a non-empty filename\n" . "\tGot $file "
    unless -s $file;
  my $fh;
  if ( $file =~ m/\.gz\Z/ ) {
    $fh = new IO::Uncompress::Gunzip $file
      || confess "\nError: gzip failed: $GunzipError\n";
  }
  else {
    $fh = IO::File->new( $file, 'r' )
      || confess "\nError: unable to open file ($file) for reading: $!\n";
  }
  return $fh;
}

sub get_write_bin_fh {
  my ( $self, $file ) = @_;

  confess "\nError: get_write_bin_fh() expects a filename\n" unless $file;
  my $fh = IO::File->new( $file, 'w' )
    || confess "\nError: unable to open file ($file) for writing: $!\n";
  binmode $fh;
  return $fh;
}
sub clean_line {
    my ($self, $line) = @_;

    if ($line =~ m/\A([\.\-\=\:\/\t\s\w\d]+)\Z/)
    {
        return $1;
    }
    else
    {
        warn "ignoring: $line";
    }
    return undef;
}

no Moose::Role;

1;
