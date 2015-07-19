use 5.10.0;
use strict;
use warnings;

package Seq::Fetch;
# ABSTRACT: Class for fetching files from UCSC
# VERSION

=head1 DESCRIPTION
  
  @class B<Seq::Fetch> 
  #TODO: Check description

  @example

Used in:
=for :list
* bin/fetch_files.pl
* 

Extended by: None
=cut

use Moose 2;

use namespace::autoclean;
use Scalar::Util qw/ reftype /;

use Seq::Fetch::Files;
use Seq::Fetch::Sql;

use DDP;

with 'Seq::Role::ConfigFromFile', 'MooX::Role::Logger';

# TODO: add --force option to overwrite existing data

has act                => ( is => 'ro', isa => 'Bool', );
has verbose            => ( is => 'ro', isa => 'Bool', );
has genome_name        => ( is => 'ro', isa => 'Str', required => 1, );
has genome_description => ( is => 'ro', isa => 'Str', required => 1, );
has genome_chrs => (
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
    $self->_logger->info( "about to fetch sql data for: " . $track->name )
      if $self->verbose;
    $track->write_sql_data;
  }
}

sub fetch_genome_size_tracks {
  my $self                     = shift;
  my $genome_sized_tracks_aref = $self->genome_sized_tracks;
  for my $track (@$genome_sized_tracks_aref) {
    $self->_logger->info( "about to fetch data for: " . $track->name ) if $self->verbose;
    $track->fetch_files;
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
      for my $attr (qw/ genome_name genome_index_dir act verbose /) {
        $sparse_track->{$attr} = $href->{$attr};
      }
      push @{ $new_hash{sparse_tracks} }, Seq::Fetch::Sql->new($sparse_track);
    }
    for my $genome_track ( @{ $href->{genome_sized_tracks} } ) {
      for my $attr (qw/ genome_name genome_chrs genome_index_dir act verbose /) {
        $genome_track->{$attr} = $href->{$attr};
      }
      push @{ $new_hash{genome_sized_tracks} }, Seq::Fetch::Files->new($genome_track);
    }
    for my $attrib (
      qw/ genome_name genome_description genome_chrs genome_raw_dir
      verbose act /
      )
    {
      $new_hash{$attrib} = $href->{$attrib} || "";
    }
    return $class->SUPER::BUILDARGS( \%new_hash );
  }
}

__PACKAGE__->meta->make_immutable;

1;
