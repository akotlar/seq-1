use 5.10.0;
use strict;
use warnings;

package Seq::Fetch;
# ABSTRACT: Class for fetching files from UCSC
# VERSION

use Moose 2;

use namespace::autoclean;
use Scalar::Util qw/ reftype /;

with 'Seq::Role::ConfigFromFile';

has genome_name        => ( is => 'ro', isa => 'Str', required => 1, );
has genome_description => ( is => 'ro', isa => 'Str', required => 1, );
has genome_chrs        => (
  is       => 'ro',
  isa      => 'ArrayRef[Str]',
  traits   => ['Array'],
  required => 1,
);

# for now, `genome_raw_dir` is really not needed since the other tracks
#   specify a directory and file to use for each feature
has genome_raw_dir => ( is => 'ro', isa => 'Str', required => 1 );
has genome_sized_tracks => (
  is       => 'ro',
  isa      => 'ArrayRef[Seq::Fetch::Files]',
  required => 1,
);
has sparse_tracks => (
  is  => 'ro',
  isa => 'ArrayRef[Seq::Fetch::Sql]',
);

sub fetch_sparse_tracks {
  my $self               = shift;
  my $sparse_tracks_aref = $self->sparse_tracks;
  for my $track (@$sparse_tracks_aref) {
    $track->write_sql_data;
  }
}

sub say_fetch_genome_size_tracks {
  my ( $self, $fh ) = @_;
  confess "say_fetch_genome_size_tracks expects an open filehandle"
    unless openhandle($fh);

  my $genome_sized_tracks = $self->genome_sized_tracks;
  for my $track (@$genome_sized_tracks) {
    say $fh $track->say_fetch_files_script;
  }
}

sub say_process_genome_size_tracks {
  my ( $self, $fh ) = @_;
  confess "say_process_genome_size_tracks expects an open filehandle"
    unless openhandle($fh);

  my $genome_sized_tracks = $self->genome_sized_tracks;
  for my $track (@$genome_sized_tracks) {
    say $fh $track->say_process_files_script
      if $track->say_process_files_script;
  }
}

sub BUILDARGS {
  my $class = shift;
  my $href  = $_[0];
  if ( scalar @_ > 1 || reftype($href) ne "HASH" ) {
    confess "Error: Seq::Fetch Expected hash reference";
  }
  else {
    my %new_hash;
    for my $sparse_track ( @{ $href->{sparse_tracks} } ) {
      $sparse_track->{genome_name}      = $href->{genome_name};
      $sparse_track->{genome_index_dir} = $href->{genome_index_dir};
      push @{ $new_hash{sparse_tracks} }, Seq::Fetch::Sql->new($sparse_track);
    }
    for my $genome_track ( @{ $href->{genome_sized_tracks} } ) {
      $genome_track->{genome_chrs}      = $href->{genome_chrs};
      $genome_track->{genome_index_dir} = $href->{genome_index_dir};
      push @{ $new_hash{genome_sized_tracks} }, Seq::Fetch::Files->new($genome_track);
    }
    for my $attrib (qw/ genome_name genome_description genome_chrs genome_raw_dir /) {
      $new_hash{$attrib} //= $href->{$attrib} || "";
    }
    return $class->SUPER::BUILDARGS( \%new_hash );
  }
}

__PACKAGE__->meta->make_immutable;

1;
