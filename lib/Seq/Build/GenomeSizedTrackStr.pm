use 5.10.0;
use strict;
use warnings;

package Seq::Build::GenomeSizedTrackStr;
# ABSTRACT: Builds a plain text genome used for binary genome creation
# VERSION
=head1 DESCRIPTION

  @class B<Seq::Build::GenomeSizedTrackStr>

  TODO: Add description
  Stores a String representation of a genome, as well as the length of each chromosome in the genome.
  Is a single responsibility class with no public functions. 

Used in:
=for :list
* Seq/Build/SparseTrack
* Seq/Build

Extended in: None

=cut

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
#TODO: enumerate where this is used, and make sure we're consistent with 0 vs 1 index
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
  my $genome_str       = '';

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

    # hash to hold temporary chromosome strings
    my %seq_of_chr;

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
        if ( $line =~ m/\A>([\w\d]+)/ ) {
          $chr = $1;
          if ( grep { /$chr/ } $self->all_genome_chrs ) {
            $wanted_chr = 1;
          }
          else {
            $self->_logger->info(
              "skipping unrecognized chromsome while building gneome str: $chr ");
            $wanted_chr = 0;
          }
        }
        elsif ( $wanted_chr && $line =~ m/(\A[ATCGNatcgn]+)\z/xmi ) {
          $seq_of_chr{$chr} .= uc $1;
        }

        # warn if a single file does not appear to have a vaild chromosome - concern
        #   is that it's not in fasta format
        if ( $. == 2 and !$wanted_chr ) {
          (
            my $err_msg =
              qq{WARNING: found data for $chr in $local_file but 
            '$chr' is not a valid chromsome for $genome_name; ensure chromsomes
            are in fasta format")}
          ) =~ s/\n/ /xmi;
          $self->_logger->info($err_msg);
          warn $err_msg;
        }
      }
    }

    # build final genome string and chromosome off-set hash
    for my $chr ( $self->all_genome_chrs ) {
      if ( exists $seq_of_chr{$chr} && defined $seq_of_chr{$chr} ) {
        $self->set_chr_len( $chr => length $genome_str );
        $genome_str .= $seq_of_chr{$chr};
        $seq_of_chr{$chr} = ();
      }
      else {
        (
          my $err_msg =
            qq{did not find chromosome data for required chromosome
          $chr while building genome for $self->name}
        ) =~ s/\n/ /xmi;
        $self->_logger->info($err_msg);
        say $err_msg;
        exit(1);
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
