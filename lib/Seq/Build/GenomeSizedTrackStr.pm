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

use DDP;

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
# TODO: enumerate where this is used, and make sure we're consistent with 0 vs 1 index
# NOTE: this is only used for building - e.g., Seq::Build, Seq::Build::* packages
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
  my $msg = sprintf( "genome length: %d", $self->genome_length );
  $self->_logger->info($msg);
  say $msg;
}

sub _build_str_genome {
  my $self = shift;

  $self->_logger->info('starting to build string genome');

  # prepare output dir, as needed, and files
  $self->genome_index_dir->mkpath unless ( -d $self->genome_index_dir );
  my $chr_len_file     = $self->genome_offset_file;
  my $genome_file      = $self->genome_str_file;
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

    for my $file ( $self->all_local_files ) {
      unless ( -f $file ) {
        my $msg = "ERROR: cannot find $file";
        $self->_logger->error($msg);
        say $msg;
        exit(1);
      }
      my $in_fh      = $self->get_read_fh($file);
      my $wanted_chr = 0;
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
            my $msg = "skipping unrecognized chromsome: $chr";
            $self->_logger->warn($msg);
            warn $msg . "\n";
            $wanted_chr = 0;
          }
        }
        elsif ( $wanted_chr && $line =~ m/(\A[ATCGNatcgn]+)\z/xmi ) {
          $seq_of_chr{$chr} .= uc $1;
        }

        # warn if a file does not appear to have a vaild chromosome - concern
        #   that it's not in fasta format
        if ( $. == 2 and !$wanted_chr ) {
          my $err_msg = sprintf(
            "WARNING: Found %s in %s but '%s' is not a valid chromsome for %s.
            You might want to ensure %s is a valid fasta file.", $chr, $file, $self->name, $file
          );
          $err_msg =~ s/[\s\n]+/ /xms;
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
