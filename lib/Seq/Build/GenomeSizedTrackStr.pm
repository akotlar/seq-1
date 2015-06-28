use 5.10.0;
use strict;
use warnings;

package Seq::Build::GenomeSizedTrackStr;
# ABSTRACT: Builds a plain text genome used for binary genome creation
# VERSION

use Moose 2;

use Carp qw/ confess croak /;
use File::Path;
use File::Spec;
use namespace::autoclean;
use YAML::XS qw/ Dump LoadFile /;

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
    exists_chr_len     => 'exists',
    char_genome_length => 'get',
    set_chr_len        => 'set',
  },
);

sub BUILD {
  my $self = shift;
  $self->_logger->info( join "\t", 'genome length', $self->genome_length );
}

sub _build_str_genome {
  my $self = shift;

  $self->_logger->info('starting to build string genome');

  my $local_dir   = File::Spec->canonpath( $self->local_dir );
  my @local_files = $self->all_local_files;

  # setup genome string files
  my $dir              = File::Spec->canonpath( $self->genome_index_dir );
  my $chr_len_name     = join ".", $self->name, $self->type, 'chr_len', 'dat';
  my $genome_name      = join ".", $self->name, $self->type, 'str', 'dat';
  my $chr_len_file     = File::Spec->catfile( $dir, $chr_len_name );
  my $genome_file      = File::Spec->catfile( $dir, $genome_name );
  my $genome_file_size = -s $genome_file;


  if ( -s $chr_len_file && $genome_file_size ) {

    $self->_logger->info('about to read genome string');

    my $fh = $self->get_read_fh($genome_file);
    read $fh, $genome_str, $genome_file_size;
    my $chr_len_href = LoadFile($chr_len_file);
    map { $self->set_chr_len( $_ => $chr_len_href->{$_} ) } keys %$chr_len_href;

    $self->_logger->info('read chrome length offsets');
  }
  else {

    $self->_logger->info("building genome string");

    my %seq_of_chr; # added this to do the munging ...

    for ( my $i = 0; $i < @local_files; $i++ ) {
      my $file        = $local_files[$i];
      my $local_file  = File::Spec->catfile( $local_dir, $file );
      my $in_fh       = $self->get_read_fh($local_file);
      my @file_fields = split( /\./, $file );
      my $wanted_chr  = 0;
      my $chr;

      while ( my $line = $in_fh->getline() ) {
        chomp $line;
        $line =~ s/\s+//g;
        if ($line =~ m/\A>([\w\d]+)/) {
          $chr = $1;
          if (grep {/$chr/} $self->all_genome_chrs ) {
            $wanted_chr = 1;
          }
          else {
            $self->warn("skipping $chr");
            $wanted_chr = 0;
          }
        }
        if ( $wanted_chr && $line =~ m/(\A[ATCGNatcgn]+)\z/xmi ) {
          $seq_of_chr{$chr} .= uc $1;
        }
        else {
          $self->_logger->info("skipping unrecognized chromsome while building gneome str: $chr ");
        }
      }
    }

    # build final genome string
    my $genome_str = '';
    for my $chr ( $self->all_genome_chrs ) {
      if ( exists $seq_of_chr{$chr} && defined $seq_of_chr{$chr} ) {
        $genome_str .= $seq_of_chr{$chr};
        $seq_of_chr{$chr} = ( );
      }
      else {
        croak "did not find chromosome data for required chromosome,"
        . $chr . " while building genome for: " . $self->name ;
      }
    }

    my $fh = $self->get_write_fh($genome_file);
    print {$fh} $genome_str;

    $fh = $self->get_write_fh($chr_len_file);
    print {$fh} Dump( $self->chr_len );
  }
  $self->_logger->info('finished building string genome');
  return $genome_str;
}

__PACKAGE__->meta->make_immutable;

1;
