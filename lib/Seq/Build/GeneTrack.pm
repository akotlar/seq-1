use 5.10.0;
use strict;
use warnings;

package Seq::Build::GeneTrack;
# ABSTRACT: Builds Gene Tracks and places into MongoDB instance.
# VERSION

use Moose 2;

use Carp qw/ confess /;
use Cpanel::JSON::XS;
use File::Path qw/ make_path /;
use namespace::autoclean;

use Seq::Gene;

extends 'Seq::Build::SparseTrack';
with 'Seq::Role::IO';

sub build_gene_db {
  my $self = shift;

  # defensively drop anything if the collection already exists
  $self->mongo_connection->_mongo_collection( $self->name )->drop;

  # input
  my $local_dir  = File::Spec->canonpath( $self->local_dir );
  my $local_file = File::Spec->catfile( $local_dir, $self->local_file );
  my $in_fh      = $self->get_read_fh($local_file);

  # # output
  # my $out_dir = File::Spec->canonpath( $self->genome_index_dir );
  # make_path($out_dir);
  # my $out_file_name =
  #   join( ".", $self->genome_name, $self->name, $self->type, 'json' );
  # my $out_file_path = File::Spec->catfile( $out_dir, $out_file_name );
  # my $out_fh = $self->get_write_fh($out_file_path);

  my %ucsc_table_lu = (
    alignID    => 'transcript_id',
    chrom      => 'chr',
    cdsEnd     => 'coding_end',
    cdsStart   => 'coding_start',
    exonEnds   => 'exon_ends',
    exonStarts => 'exon_starts',
    strand     => 'strand',
    txEnd      => 'transcript_end',
    txStart    => 'transcript_start',
  );
  my ( %header, %exon_sites, %flank_exon_sites,  %transcript_start_sites );
  my $prn_count = 0;

  while (<$in_fh>) {
    chomp $_;
    my @fields = split( /\t/, $_ );
    if ( $. == 1 ) {
      map { $header{ $fields[$_] } = $_ } ( 0 .. $#fields );
      next;
    }
    my %data = map { $_ => $fields[ $header{$_} ] }
      ( @{ $self->gene_fields_aref }, $self->all_features );

    # skip sites on alt chromosome builds
    next unless $self->exists_chr_len( $data{chrom} );

    # prepare basic gene data
    my %gene_data = map { $ucsc_table_lu{$_} => $data{$_} } keys %ucsc_table_lu;
    $gene_data{exon_ends}   = [ split( /\,/, $gene_data{exon_ends} ) ];
    $gene_data{exon_starts} = [ split( /\,/, $gene_data{exon_starts} ) ];
    $gene_data{genome_track} = $self->genome_track_str;

    # prepare alternative names for gene
    my %alt_names = map { $_ => $data{$_} if exists $data{$_} } ( $self->all_features );

    my $gene = Seq::Gene->new( \%gene_data );
    $gene->set_alt_names(%alt_names);

    # get intronic flanking site annotations
    my @flank_exon_sites = $gene->get_flanking_sites();
    for my $site (@flank_exon_sites) {
      my $site_href = $site->as_href;
      # $self->mongo_connection->_mongo_collection( $self->name )->insert($site_href);
      $self->insert($site_href);
      $self->execute if $self->counter > $self->bulk_insert_threshold;
      $flank_exon_sites{ $site->abs_pos }++;
    }

    # get exon annotations
    my @exon_sites = $gene->get_transcript_sites();
    for my $site (@exon_sites) {
      my $site_href = $site->as_href;
      # $self->mongo_connection->_mongo_collection( $self->name )->insert($site_href);
      $self->insert($site_href);
      $self->execute if $self->counter > $self->bulk_insert_threshold;
      $exon_sites{ $site->abs_pos }++;
    }
    push @{ $transcript_start_sites{ $gene->transcript_start } }, $gene->transcript_end;
  }
  my $sites_href = { flank_exon_sites => \%flank_exon_sites,
                     exon_sites => \%exon_sites,
                     transcript_start_sites => \%transcript_start_sites,
  };
  return ( $sites_href );
}

__PACKAGE__->meta->make_immutable;

1;
