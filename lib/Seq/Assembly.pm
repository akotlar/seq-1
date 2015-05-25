use 5.10.0;
use strict;
use warnings;

package Seq::Assembly;
# ABSTRACT: A class for assembly information
# VERSION

use Moose 2;

use Carp qw/ croak /;
use namespace::autoclean;
use Scalar::Util qw/ reftype /;
use Path::Tiny qw/ path /;

use DDP;

use Seq::Config::GenomeSizedTrack;
use Seq::Config::SparseTrack;

with 'Seq::Role::ConfigFromFile';

has genome_name        => ( is => 'ro', isa => 'Str', required => 1, );
has genome_description => ( is => 'ro', isa => 'Str', required => 1, );
has genome_db_dir      => ( is => 'ro', isa => 'Str', required => 1, );
has genome_index_dir   => ( is => 'ro', isa => 'Str', required => 1, );
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

  if ( scalar @_ > 1 || reftype($href) ne "HASH" )
  {
    confess "Error: $class expects hash reference.\n";
  }
  else
  {
    my %hash;

    #to avoid subtle chdir issues in a multi-user env, just make the genome_index_dir correct from the getgo
    $href->{genome_index_dir} = path( $href->{genome_index_dir} )->absolute( $href->{genome_db_dir} );
    $href->{genome_index_dir}->mkpath; #makes or returns undef, errors are trapped & exception thrown on error
    $href->{genome_index_dir} = $href->{genome_index_dir}->stringify;

    for my $sparse_track ( @{ $href->{sparse_tracks} } )
    {
      $sparse_track->{genome_name} = $href->{genome_name};
      if ( $sparse_track->{type} eq "gene" )
      {
        push @{ $hash{gene_tracks} }, Seq::Config::SparseTrack->new($sparse_track);
      }
      elsif ( $sparse_track->{type} eq "snp" )
      {
        push @{ $hash{snp_tracks} }, Seq::Config::SparseTrack->new($sparse_track);
      }
      else
      {
        croak sprintf( "unrecognized genome track type %s\n", $sparse_track->{type} );
      }
    }
    for my $gst ( @{ $href->{genome_sized_tracks} } )
    {
      croak sprintf( "unrecognized genome track type %s\n", $gst->{type} )
        unless ( $gst->{type} eq 'genome' or $gst->{type} eq 'score' );
      $gst->{genome_chrs}      = $href->{genome_chrs};
      $gst->{genome_index_dir} = $href->{genome_index_dir}; #do we need this?
      push @{ $hash{genome_sized_tracks} }, Seq::Config::GenomeSizedTrack->new($gst);
    }
    for my $attrib (
      qw/ genome_name genome_description genome_chrs genome_index_dir
      genome_hasher genome_scorer debug wanted_chr genome_db_dir /
      )
    {
      $hash{$attrib} = $href->{$attrib};
    }
    return $class->SUPER::BUILDARGS( \%hash );
  }
}

__PACKAGE__->meta->make_immutable;

1;
