use 5.10.0;
use strict;
use warnings;

# DEPRECIATED PACKAGE
# DEPRECIATED PACKAGE
# DEPRECIATED PACKAGE
# DEPRECIATED PACKAGE

package Seq::Build::TxTrack;
# ABSTRACT: Builds Gene Tracks and places into BerkeleyDB instance.
# VERSION

=head1 DESCRIPTION

  @class Seq::Build::TxTrack
  This class takes tab-delimited gene track information (as might be prepared
  by the Seq::Fetch and Seq::Fetch::* packages) and 1) creates a database of all
  Seq::Gene objects and 2) creates a file that enumerates the ranges of genes
  within the genome for `genome_hasher`.

  @example

Used in:
=for :list
* Seq::Build

Extended by: None

=cut

use Moose 2;

use File::Path qw/ make_path /;
use namespace::autoclean;

use Seq::Gene;

use DDP;

extends 'Seq::Build::SparseTrack';
with 'Seq::Role::IO';

sub insert_transcript_seq {
  my $self = shift;

  # input
  my $local_dir  = File::Spec->canonpath( $self->local_dir );
  my $local_file = File::Spec->catfile( $local_dir, $self->local_file );
  my $in_fh      = $self->get_read_fh($local_file);

  # genome output
  my $index_dir = File::Spec->canonpath( $self->genome_index_dir );
  make_path($index_dir) unless -f $index_dir;

  # gene region files
  my $gene_region_name = join( ".", $self->name, 'gene_region', 'dat' );
  my $gene_region_file = File::Spec->catfile( $index_dir, $gene_region_name );
  my $gene_region_fh = $self->get_write_fh($gene_region_file);
  say {$gene_region_fh} $self->in_gene_val;

  # dbm file
  my $dbm_name = join ".", $self->name, $self->type, 'tx', 'kch';
  my $dbm_file = File::Spec->catfile( $index_dir, $dbm_name );

  # create dbm object
  my $db = Seq::KCManager->new(
    filename => $dbm_file,
    mode     => 'create',
    # bnum => bucket number => 50-400% of expected items in the hash is optimal
    # annotated sites for hg38 is 22727477 (chr1) to 13222 (chrM) with avg of
    # 9060664 and sd of 4925631; thus, took ~1/2 of maximal number of entries
    bnum => 1_000_000,
    msiz => 512_000_000,
  );

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

    $db->db_put( $record_href->{transcript_id}, $record_href );

    say {$gene_region_fh} join "\t", $gene->transcript_start, $gene->transcript_end;
  }
}

__PACKAGE__->meta->make_immutable;

1;
