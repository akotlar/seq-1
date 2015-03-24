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

extends 'Seq::Config::GenomeSizedTrack';
with 'Seq::Role::IO', 'Seq::Role::Genome';

# str_seq stores a string in a single scalar
has genome_seq => (
  is      => 'rw',
  writer  => undef,
  default => sub { '' },
  isa     => 'Str',
  traits  => ['String'],
  handles => {
    add_seq       => 'append',
    clear_genome  => 'clear',
    genome_length => 'length',
    seq_length    => 'length',
    get_base      => 'substr', # zero-indexed
  },
  lazy => 1,
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

sub build_genome {
  my $self        = shift;
  my $local_dir   = File::Spec->canonpath( $self->local_dir );
  my @local_files = $self->all_local_files;
  my @genome_chrs = $self->all_genome_chrs;

  for ( my $i = 0; $i < @local_files; $i++ ) {
    my $file        = $local_files[$i];
    my $chr         = $genome_chrs[$i];
    my $local_file  = File::Spec->catfile( $local_dir, $file );
    my $in_fh       = $self->get_read_fh($local_file);
    my @file_fields = split( /\./, $file );

    confess "expected chromosomes and sequence files to be in the"
      . " same order but found $file with $chr\n"
      unless $chr eq $file_fields[0];

    $self->set_chr_len( $chr => $self->seq_length );

    while ( my $line = $in_fh->getline() ) {
      chomp $line;
      $line =~ s/\s+//g;
      next if ( $line =~ m/\A>/ );
      if ( $line =~ m/(\A[ATCGNatcgn]+)\Z/ ) {
        $self->add_seq( uc $1 );
      }
      else {
        confess join( "\n",
          "ERROR: Unexpected Non-Base Character.",
          "\tfile: $file ",
          "\tline: $.", "\tsequence: $line" );
      }
    }
  }
}

__PACKAGE__->meta->make_immutable;

1;
