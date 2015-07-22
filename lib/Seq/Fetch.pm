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

extends 'Seq::Assembly';

sub fetch_sparse_tracks {
  my $self = shift;

  for my $snp_track ( $self->all_snp_tracks ) {
    # extract keys from snp_track for creation of Seq::Build::SnpTrack
    my $record = $snp_track->as_href;

    # add required fields for the build track
    for my $attr ( qw/ force debug / ) {
      $record->{$attr} = $self->$attr if $self->$attr;
    }

    if ($self->verbose ) {
      my $msg = sprintf("about to fetch sql data for: %s", $snp_track->name);
      $self->_logger->info( $msg );
      say $msg;
    }

    my $obj = Seq::Fetch::Sql->new( $record );
    $obj->write_sql_data;
  }
}

sub fetch_genome_size_tracks {
  my $self = shift;

  for my $gene_track ( $self->all_gene_tracks ) {
    # extract keys from snp_track for creation of Seq::Build::SnpTrack
    my $record = $gene_track->as_href;

    # add required fields for the build track
    for my $attr ( qw/ force debug / ) {
      $record->{$attr} = $self->$attr if $self->$attr;
    }

    if ($self->verbose ) {
      my $msg = sprintf("about to fetch sql data for: %s", $gene_track->name);
      $self->_logger->info( $msg );
      say $msg;
    }

    my $obj = Seq::Fetch::Files->new( $record );
    $obj->fetch_files;
  }
}

__PACKAGE__->meta->make_immutable;

1;
