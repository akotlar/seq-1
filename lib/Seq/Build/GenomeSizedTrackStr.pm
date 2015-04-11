use 5.10.0;
use strict;
use warnings;

package Seq::Build::GenomeSizedTrackStr;
# ABSTRACT: Builds a plain text genome used for binary genome creation
# VERSION

use Moose 2;

use Carp qw/ confess /;
use File::Path;
use File::Spec;
use namespace::autoclean;
use YAML qw/ Dump LoadFile /;

extends 'Seq::Config::GenomeSizedTrack';
with 'Seq::Role::IO', 'Seq::Role::Genome', 'MooX::Role::Logger';

# str_seq stores a string in a single scalar
has genome_seq => (
  is      => 'ro',
  writer  => undef,
  isa     => 'Str',
  traits  => ['String'],
  handles => {
    add_seq       => 'append',
    clear_genome  => 'clear',
    genome_length => 'length',
    get_base      => 'substr', # zero-indexed
  },
  lazy    => 1,
  builder => '_build_str_genome',
);

# stores the 1-indexed length of each chromosome
has chr_len => (
  is      => 'rw',
  isa     => 'HashRef[Str]',
  traits  => ['Hash'],
  handles => {
    exists_chr_len => 'exists',
    get_chr_len    => 'get',
    set_chr_len    => 'set',
  },
);

sub BUILD {
  my $self = shift;
  $self->_logger->info( join "\t", 'genome length', $self->genome_length );
}

sub _build_str_genome {
  my $self = shift;

  $self->_logger->info('in _build_str_genome');

  my $local_dir   = File::Spec->canonpath( $self->local_dir );
  my @local_files = $self->all_local_files;
  my @genome_chrs = $self->all_genome_chrs;

  my $dir              = File::Spec->canonpath( $self->genome_index_dir );
  my $chr_len_name     = join ".", $self->name, $self->type, 'chr_len', 'dat';
  my $genome_name      = join ".", $self->name, $self->type, 'str', 'dat';
  my $chr_len_file     = File::Spec->catfile( $dir, $chr_len_name );
  my $genome_file      = File::Spec->catfile( $dir, $genome_name );
  my $genome_file_size = -s $genome_file;
  my $genome_str       = '';

  if ( -s $chr_len_file && $genome_file_size ) {

    my $fh = $self->get_read_fh($genome_file);
    read $fh, $genome_str, $genome_file_size;

    $self->_logger->info('read genome string');

    my $chr_len_href = LoadFile($chr_len_file);
    map { $self->set_chr_len( $_ => $chr_len_href->{$_} ) } keys %$chr_len_href;

    $self->_logger->info('read chrome length offsets');

  }
  else {

    $self->_logger->info('no previous genome detected; building genome string');

    for ( my $i = 0; $i < @local_files; $i++ ) {
      my $file        = $local_files[$i];
      my $chr         = $genome_chrs[$i];
      my $local_file  = File::Spec->catfile( $local_dir, $file );
      my $in_fh       = $self->get_read_fh($local_file);
      my @file_fields = split( /\./, $file );

      confess "expected chromosomes and sequence files to be in the"
        . " same order but found $file with $chr\n"
        unless $chr eq $file_fields[0];

      $self->set_chr_len( $chr => length $genome_str );

      while ( my $line = $in_fh->getline() ) {
        chomp $line;
        $line =~ s/\s+//g;
        next if ( $line =~ m/\A>/ );
        if ( $line =~ m/(\A[ATCGNatcgn]+)\Z/ ) {
          $genome_str .= uc $1;
        }
        else {
          confess join( "\n",
            "ERROR: Unexpected Non-Base Character.",
            "\tfile: $file ",
            "\tline: $.", "\tsequence: $line" );
        }
      }
    }

    my $fh = $self->get_write_fh($genome_file);
    print {$fh} $genome_str;

    $fh = $self->get_write_fh($chr_len_file);
    print {$fh} Dump( $self->chr_len );
  }
  return $genome_str;
}

__PACKAGE__->meta->make_immutable;

1;
