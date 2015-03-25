use 5.10.0;
use strict;
use warnings;

package Seq::Role::IO;

# ABSTRACT: A moose role for all of our file handle needs
# VERSION

use Moose::Role;

use Carp qw/ confess croak /;
use IO::File;
use IO::Compress::Gzip qw/ $GzipError /;
use IO::Uncompress::Gunzip qw/ $GunzipError /;

# tried various ways of assigning this to an attrib, with the intention that
# one could change the taint checking characters allowed but this is the simpliest
# one that worked; wanted it precompiled to improve the speed of checking
my $taint_check_re = qr{\A([\.\-\=\:\/\t\s\w\d]+)\Z};

sub get_write_fh {
    my ( $class, $file ) = @_;
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
    my ( $class, $file ) = @_;

    croak "\nError: get_read_fh() expects a non-empty filename\n"
      . "\tGot $file "
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
    my ( $class, $file ) = @_;

    confess "\nError: get_write_bin_fh() expects a filename\n" unless $file;
    my $fh = IO::File->new( $file, 'w' )
      || confess "\nError: unable to open file ($file) for writing: $!\n";
    binmode $fh;
    return $fh;
}

sub clean_line {
    my ( $class, $line ) = @_;

    if ( $line =~ m/$taint_check_re/ ) {
        return $1;
    }
    else {
        warn "ignoring: $line";
    }
    return;
}

no Moose::Role;

1;