use 5.10.0;
use strict;
use warnings;

package Seq::Assembly;
# ABSTRACT: A class for assembly information
# VERSION

=head1 DESCRIPTION

  @class B<Seq::Assembly>
  # TODO: Check description

  @example

Used in: None

Extended by:
=for :list
* Seq::Annotate
* Seq::Build

Uses:
=for :list
* Seq::Config::GenomeSizedTrack
* Seq::Config::SparseTrack

=cut

use Moose 2;

use Carp qw/ croak confess/;
use namespace::autoclean;
use Scalar::Util qw/ reftype /;
use Path::Tiny qw/ path /;

use Seq::Config::GenomeSizedTrack;
use Seq::Config::SparseTrack;

use DDP; # for debugging

with 'Seq::Role::ConfigFromFile', 'MooX::Role::Logger';

my @_attributes = qw/ genome_name genome_description genome_chrs genome_index_dir
  genome_hasher genome_scorer debug wanted_chr debug/;

has genome_name        => ( is => 'ro', isa => 'Str', required => 1, );
has genome_description => ( is => 'ro', isa => 'Str', required => 1, );

# TODO: kotlar; I commented out `genome_db_dir`, since what we really want is
# `genome_index_dir`, and that is already required
#has genome_db_dir      => ( is => 'ro', isa => 'Str', required => 1, );

=property @public {Str} genome_index_dir

  The path (relative or absolute) to the index folder, which contains:
  1) the binary GenomeSizedTrack of the reference genome, 2) the chr offset
  file, 3) all SparseTrack database files, and 4) all binary GenomeSizedTrack
  files of the optional 'score' and 'cadd' types.

  Defined in the required input yaml config file, as a key : value pair, and
  used by:
  @role Seq::Role::ConfigFromFile

  The existance of this directory is checked in Seq::Annotate::BUILDARGS

@example genome_index_dir: ./hg38/index
=cut

has genome_index_dir => ( is => 'ro', isa => 'Str', required => 1, );

has genome_chrs => (
  is       => 'ro',
  isa      => 'ArrayRef[Str]',
  traits   => ['Array'],
  required => 1,
  handles  => { all_genome_chrs => 'elements', },
);
has genome_sized_tracks => (
  is      => 'ro',
  isa     => 'ArrayRef[Seq::Config::GenomeSizedTrack]',
  traits  => ['Array'],
  handles => {
    all_genome_sized_tracks => 'elements',
    add_genome_sized_track  => 'push',
  },
);
has snp_tracks => (
  is      => 'ro',
  isa     => 'ArrayRef[Seq::Config::SparseTrack]',
  traits  => ['Array'],
  handles => {
    all_snp_tracks => 'elements',
    add_snp_track  => 'push',
  },
);
has gene_tracks => (
  is      => 'ro',
  isa     => 'ArrayRef[Seq::Config::SparseTrack]',
  traits  => ['Array'],
  handles => {
    all_gene_tracks => 'elements',
    add_gene_track  => 'push',
  },
);

=property @public dbm_dry_run

  Deprecated: If you just wanted to test annotation without the database engine
  locally installed. Allowed you to skip writing a (KyotoCabinet or BerkleyDB)
  database files.

=cut

has dbm_dry_run => (
  is      => 'ro',
  isa     => 'Bool',
  default => 0,
);

has debug => (
  is      => 'ro',
  isa     => 'Bool',
  default => 0,
);

sub BUILDARGS {
  my $class = shift;
  my $href  = $_[0];

  if ( scalar @_ > 1 || reftype($href) ne "HASH" ) {
    confess "Error: $class expects hash reference.\n";
  }
  else {
    my %hash;

    $href->{genome_index_dir} = path( $href->{genome_index_dir} )->absolute;

    # is genome_index_dir a directory?
    if ( !$href->{genome_index_dir}->is_dir ) {
      # is the supplied genome_index_dir a file?
      if ( $href->{genome_index_dir}->is_file ) {
        my $err_msg =
          sprintf( "ERROR: '%s' exists and is a file.", $href->{genome_index_dir} );
        warn $err_msg . "\n";
        $class->_logger->error($err_msg);
        exit 1;
      }

      # make the specified genome_index_dir.
      if ( $href->{genome_index_dir}->mkpath ) {
        my $err_msg = sprintf( "ERROR: failed to create genome_index_dir: '%s'",
          $href->{genome_index_dir} );
        warn $err_msg . "\n";
        $class->_logger->error($err_msg);
        exit 1;
      }
    }

    $href->{genome_index_dir} = $href->{genome_index_dir}->stringify;

    if ( $href->{debug} ) {
      my $msg =
        sprintf( "The absolute genome_index_dir path is %s", $href->{genome_index_dir} );
      say $msg;
      $class->_logger->info($msg);
    }

    for my $sparse_track ( @{ $href->{sparse_tracks} } ) {

      $sparse_track->{genome_name}      = $href->{genome_name};
      $sparse_track->{genome_index_dir} = $href->{genome_index_dir};
      if ( $sparse_track->{type} eq "gene" ) {
        push @{ $hash{gene_tracks} }, Seq::Config::SparseTrack->new($sparse_track);
      }
      elsif ( $sparse_track->{type} eq "snp" ) {
        push @{ $hash{snp_tracks} }, Seq::Config::SparseTrack->new($sparse_track);
      }
      else {
        croak sprintf( "unrecognized genome track type %s\n", $sparse_track->{type} );
      }
    }
    for my $gst ( @{ $href->{genome_sized_tracks} } ) {
      if ( $gst->{type} eq 'genome' or $gst->{type} eq 'score' or $gst->{type} eq 'cadd' )
      {
        $gst->{genome_chrs}      = $href->{genome_chrs};
        $gst->{genome_index_dir} = $href->{genome_index_dir};

        if ( $href->{debug} ) {
          say "We are in the " . $gst->{type} . " portion of the loop";
          say "Here is what we are passing to Seq::Config::GenomeSizedTrack";
          p $gst;
        }
        push @{ $hash{genome_sized_tracks} }, Seq::Config::GenomeSizedTrack->new($gst);

        say "We got past Seq::Config::GenomeSizedTrack instantiation" if $href->{debug};
      }
      else {
        croak sprintf( "unrecognized genome track type %s\n", $gst->{type} );
      }
    }
    for my $attrib (@_attributes) {
      $hash{$attrib} = $href->{$attrib};
    }
    return $class->SUPER::BUILDARGS( \%hash );
  }
}

__PACKAGE__->meta->make_immutable;

1;
