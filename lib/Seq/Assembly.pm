use 5.10.0;
use strict;
use warnings;

package Seq::Assembly;
# ABSTRACT: A class for assembly information
# VERSION
=head1 DESCRIPTION
  
  @class B<Seq::Assembly>
  #TODO: Check description
  
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

use Carp qw/ croak /;
use namespace::autoclean;
use Scalar::Util qw/ reftype /;
use Path::Tiny qw/ path /;

use Seq::Config::GenomeSizedTrack;
use Seq::Config::SparseTrack;

with 'Seq::Role::ConfigFromFile';

my @_attributes = qw/ genome_name genome_description genome_chrs genome_index_dir
      genome_hasher genome_scorer debug wanted_chr genome_db_dir debug/;
has _attributes => (
  is => 'ro',
  isa => 'ArrayRef',
  init_arg => undef,
  default => sub{return \@_attributes}
);

has genome_name        => ( is => 'ro', isa => 'Str', required => 1, );
has genome_description => ( is => 'ro', isa => 'Str', required => 1, );
has genome_db_dir      => ( is => 'ro', isa => 'Str', required => 1, );

=property @public {Str} genome_index_dir
  
  The path (relative or absolute) to the index folder, which contains the binary reference genome file, chr offset file,
  the 'gene' type database (current extension .kch, but could be any, like .dbm, depending on the database engine used),
  binary 'score' type sparse_track files, 'score' type offset files, and 'cadd' type binary spare_track files.

  Defined in the required input yaml config file, as a key : value pair, and is injected automatically by
  @role Seq::Role::ConfigFromFile

@example genome_index_dir: ./hg38/index
=cut
has genome_index_dir   => ( is => 'ro', isa => 'Str', required => 1, );

has genome_chrs        => (
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

  Deprecated: If you just wanted to test annotation without the database engine locally installed.
  Allowed you to skup writing a (KyotoCabinet or BerkleyDB) file. For testing.

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

    # to avoid subtle chdir issues in a multi-user env, just make the genome_index_dir correct from the getgo
    $href->{genome_index_dir} =
      path( $href->{genome_index_dir} )->absolute( $href->{genome_db_dir} );
    # makes or returns undef, errors are trapped & exception thrown on error
    # TODO: you're 100% right but this can be a bit cryptic when it happens ... i.e., how can the error msg
    #       be helpful to the user?
    $href->{genome_index_dir}->mkpath;
    $href->{genome_index_dir} = $href->{genome_index_dir}->stringify;

    for my $sparse_track ( @{ $href->{sparse_tracks} } ) {
      $sparse_track->{genome_name} = $href->{genome_name};
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
        push @{ $hash{genome_sized_tracks} }, Seq::Config::GenomeSizedTrack->new($gst);
      }
      # elsif ( $gst->{type} eq 'cadd' ) {
      #   $gst->{genome_chrs}      = $href->{genome_chrs};
      #   $gst->{genome_index_dir} = $href->{genome_index_dir};
      #   $hash{cadd_track}        = Seq::Config::GenomeSizedTrack->new($gst);
      # }
      else {
        croak sprintf( "unrecognized genome track type %s\n", $gst->{type} );
      }
    }
    for my $attrib (@{$href->{_attributes} } )
    {
      $hash{$attrib} = $href->{$attrib};
    }
    return $class->SUPER::BUILDARGS( \%hash );
  }
}

__PACKAGE__->meta->make_immutable;

1;
