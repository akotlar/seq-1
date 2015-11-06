use 5.10.0;
use strict;
use warnings;

package Seq::Assembly;

our $VERSION = '0.001';

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
use MooseX::Types::Path::Tiny qw/ AbsPath /;

use Carp qw/ croak confess/;
use namespace::autoclean;
use Scalar::Util qw/ reftype /;
use Path::Tiny qw/ path /;

use Seq::Config::GenomeSizedTrack;
use Seq::Config::SparseTrack;

with 'Seq::Role::ConfigFromFile'; #leaving Logger for now, for compat

my @_attributes = qw/ genome_name genome_description genome_chrs genome_index_dir
  genome_cadd genome_hasher genome_scorer debug wanted_chr debug force act/;

has genome_name        => ( is => 'ro', isa => 'Str', required => 1, );
has genome_description => ( is => 'ro', isa => 'Str', required => 1, );

=property @public {Str} genome_index_dir

  The path (relative or absolute) to the index folder, which contains:
  1) the binary GenomeSizedTrack of the reference genome, 2) the chr offset
  file, 3) all SparseTrack database files, and 4) all binary GenomeSizedTrack
  files of the optional 'score' and 'cadd' types.

  Defined in the required input yaml config file, as a key : value pair, and
  used by:
  @role Seq::Role::ConfigFromFile

  The existance of this directory is checked in Seq::Annotate::BUILDARGS

@example genome_index_dir: hg38/index
=cut

has genome_index_dir => ( is => 'ro', isa => AbsPath, coerce => 1, required => 1, );

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

has force => (
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

    # NOTE: handle essential directories
    #   whether they are used depends on the context of subsequent calls
    for my $req_dir (qw/ genome_index_dir genome_raw_dir/) {
      if ( defined $href->{$req_dir} ) {
        $href->{$req_dir} = path( $href->{$req_dir} );
      }
      else {
        $href->{$req_dir} = path(".");
        my $msg = sprintf( "WARNING: missing %s; defaulted to: %s",
          $req_dir, $href->{$req_dir}->absolute->stringify );
        say $msg;
      }
    }

    if ( $href->{debug} ) {
      my $msg =
        sprintf( "genome_index_dir: %s", $href->{genome_index_dir}->absolute->stringify );
      say $msg;
      $msg = sprintf( "genome_raw_dir: %s", $href->{genome_raw_dir}->absolute->stringify );
      say $msg;
    }

    for my $sparse_track ( @{ $href->{sparse_tracks} } ) {
      # give all sparse tracks some needed information
      for my $attr (qw/ genome_raw_dir genome_index_dir genome_chrs /) {
        $sparse_track->{$attr} = $href->{$attr};
      }

      if ( $sparse_track->{type} eq 'gene' ) {
        push @{ $hash{gene_tracks} }, Seq::Config::SparseTrack->new($sparse_track);
      }
      elsif ( $sparse_track->{type} eq 'snp' ) {
        push @{ $hash{snp_tracks} }, Seq::Config::SparseTrack->new($sparse_track);
      }
      else {
        croak sprintf( "unrecognized genome track type %s\n", $sparse_track->{type} );
      }
    }

    for my $gst ( @{ $href->{genome_sized_tracks} } ) {
      # give all genome size tracks some needed information
      for my $attr (qw/ genome_raw_dir genome_index_dir genome_chrs /) {
        $gst->{$attr} = $href->{$attr};
      }

      if ( $gst->{type} eq 'genome'
        or $gst->{type} eq 'score'
        or $gst->{type} eq 'cadd' )
      {
        my $obj = Seq::Config::GenomeSizedTrack->new($gst);
        push @{ $hash{genome_sized_tracks} }, $obj;
      }
      else {
        croak sprintf( "unrecognized genome track type %s\n", $gst->{type} );
      }
    }
    for my $attrib (@_attributes) {
      $hash{$attrib} = $href->{$attrib} if exists $href->{$attrib};
    }
    #allows mixins to get attributes without making subclasses 
    #avoid knowitall antipatterns (defeat purpose of encapsulation in mixins)
    for my $key (keys %$href) {
      next if exists $hash{$key};
      $hash{$key} = $href->{$key};
    }
    return $class->SUPER::BUILDARGS( \%hash );
  }
}

__PACKAGE__->meta->make_immutable;

1;
