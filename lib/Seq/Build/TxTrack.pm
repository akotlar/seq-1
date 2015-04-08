use 5.10.0;
use strict;
use warnings;

package Seq::Build::TxTrack;
# ABSTRACT: Builds Gene Tracks and places into MongoDB instance.
# VERSION

use Moose 2;

use Carp qw/ confess /;
use File::Path qw/ make_path /;
use namespace::autoclean;

use Seq::Gene;

use DDP;

extends 'Seq::Build::SparseTrack';
with 'Seq::Role::IO';

sub insert_transcript_seq {
  my $self = shift;

  # defensively drop anything if the collection already exists
  # $self->mongo_connection->_mongo_collection( $self->name )->drop;

  # input
  my $local_dir  = File::Spec->canonpath( $self->local_dir );
  my $local_file = File::Spec->catfile( $local_dir, $self->local_file );
  my $in_fh      = $self->get_read_fh($local_file);

  my %ucsc_table_lu = (
    name       => 'transcript_id',
    chrom      => 'chr',
    cdsEnd     => 'coding_end',
    cdsStart   => 'coding_start',
    exonEnds   => 'exon_ends',
    exonStarts => 'exon_starts',
    strand     => 'strand',
    txEnd      => 'transcript_end',
    txStart    => 'transcript_start',
  );
  my ( %header, %exon_sites, %flank_exon_sites, %transcript_start_sites );

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

    my %alt_names = map { $_ => $data{$_} if exists $data{$_} } ( $self->all_features );
    my $gene = Seq::Gene->new( \%gene_data );
    $gene->set_alt_names(%alt_names);

    my $record_href = {
      coding_start            => $gene->coding_start,
      coding_end              => $gene->coding_end,
      exon_starts             => $gene->exon_starts,
      exon_ends               => $gene->exon_ends,
      transcript_start        => $gene->transcript_start,
      transcript_end          => $gene->transcript_end,
      transcript_id           => $gene->transcript_id,
      transcript_seq          => $gene->transcript_seq,
      transcript_annotation   => $gene->transcript_annotation,
      transcript_abs_position => $gene->transcript_abs_position,
      peptide_seq             => $gene->peptide,
    };
    $self->db_put( $record_href->{transcript_id}, $record_href );
    #$self->insert($record_href);
    #$self->execute if $self->counter > $self->bulk_insert_threshold;
  }
  #$self->execute if $self->counter;
}

__PACKAGE__->meta->make_immutable;

1;
