use 5.10.0;
use strict;
use warnings;

package Seq::Fetch;

our $VERSION = '0.001';

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

extends 'Seq::Assembly';

has act => (
  is      => 'ro',
  isa     => 'Bool',
  default => 0,
);

sub fetch_snp_data {
  my $self        = shift;
  my $tracks_aref = [ $self->all_snp_tracks ];
  return $self->_fetch_sparse_data($tracks_aref);
}

sub fetch_gene_data {
  my $self        = shift;
  my $tracks_aref = [ $self->all_gene_tracks ];
  return $self->_fetch_sparse_data($tracks_aref);
}

sub _fetch_sparse_data {
  my ( $self, $tracks_aref ) = @_;
  my %files;
  for my $track (@$tracks_aref) {

    # extract keys from snp_track for creation of Seq::Build::SnpTrack
    my $record = $track->as_href;

    # add required fields for the build track
    for my $attr (qw/ act debug /) {
      $record->{$attr} = $self->$attr if $self->$attr;
    }

    # add genome as db name
    $record->{db} = $self->genome_name;

    if ( $self->debug ) {
      my $msg = sprintf( "about to fetch sql data for: %s", $track->name );
      $self->_logger->info($msg);
      say $msg;
    }

    my $obj = Seq::Fetch::Sql->new($record);
    $files{ $track->name } = $obj->write_remote_data;

  }
  return \%files;
}

sub fetch_genome_size_data {
  my $self = shift;

  for my $track ( $self->all_genome_sized_tracks ) {
    # extract keys from snp_track for creation of Seq::Build::SnpTrack
    my $record = $track->as_href;

    # add required fields for the build track
    for my $attr (qw/ act debug /) {
      $record->{$attr} = $self->$attr if $self->$attr;
    }

    if ( $self->debug ) {
      my $msg = sprintf( "about to fetch files: %s", $track->name );
      $self->_logger->info($msg);
      say $msg;
    }

    my $obj = Seq::Fetch::Files->new($record);
    $obj->fetch_files;
  }
  return 1;
}

__PACKAGE__->meta->make_immutable;

1;
