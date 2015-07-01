use 5.10.0;
use strict;
use warnings;

package Seq::Build::GeneTrack;
# ABSTRACT: Builds Gene Tracks and places into MongoDB instance.
# VERSION

use Moose 2;

use File::Path qw/ make_path /;
use File::Spec;
use namespace::autoclean;

use Seq::Gene;
use Seq::KCManager;

extends 'Seq::Build::SparseTrack';
with 'Seq::Role::IO';

sub _get_gene_data {
  my ( $self, $chr ) = @_;

  # to return gene data
  my @gene_data;

  $self->_logger->info("starting to build gene site db for: $chr");

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
  my ( %header, %transcript_start_sites );

  while ( my $line = $in_fh->getline ) {
    chomp $line;
    my @fields = split( /\t/, $line );
    if ( !%header ) {

      map { $header{ $fields[$_] } = $_ } ( 0 .. $#fields );

      # do we have the required keys?
      $self->_check_header_keys( \%header,
        [ qw/ chrom chromStart chromEnd name cdsEnd cdsStart exonEnds strand txEnd txStart / ] );

      # do we have the optinally specified keys?
      $self->_check_header_keys( \%header, [ $self->all_features ] );
      next;
    }
    my %data = map { $_ => $fields[ $header{$_} ] }
      ( @{ $self->gene_fields_aref }, $self->all_features );

    # this also has the byproduct of skipping weird chromosomes
    next unless $data{chrom} eq $chr;

    # prepare basic gene data
    my %gene_data = map { $ucsc_table_lu{$_} => $data{$_} } keys %ucsc_table_lu;
    $gene_data{exon_ends}   = [ split( /\,/, $gene_data{exon_ends} ) ];
    $gene_data{exon_starts} = [ split( /\,/, $gene_data{exon_starts} ) ];
    $gene_data{genome_track} = $self->genome_track_str;

    # prepare alternative names for gene
    #   - the basic problem is that the type constraint on alt_names wants
    #   the hash to contain strings; without the ($data{$_}) ? $data{$_} : 'NA'
    #   there were some keys with blank values
    #   - this feels like a hack to accomidate the type constraint on alt_names
    #   attributes and will increase the db size; may just drop the keys without
    #   data in the future but it's running now so will hold off for the time
    #   being.
    my %alt_names = map { $_ => ( $data{$_} ) ? $data{$_} : 'NA' if exists $data{$_} }
      ( $self->all_features );
    $gene_data{_alt_names} = \%alt_names;

    push @gene_data, \%gene_data;
  }
  return \@gene_data;
}

sub build_gene_db_for_chr {

  my ( $self, $chr ) = @_;

  # read gene data for the chromosome
  #   if there is no usable data then we will bail out and not blank files
  #   will be created
  my $chr_data_aref = $self->_get_gene_data($chr);
  $self->_logger->info( "finished reading data for " . $chr );

  # output
  my $index_dir = File::Spec->canonpath( $self->genome_index_dir );
  make_path($index_dir) unless -f $index_dir;

  # flanking site range file
  my $gan_name = join ".", $self->name, $chr, 'gan', 'dat';
  my $gan_file = File::Spec->catfile( $index_dir, $gan_name );

  # exon site range file
  my $ex_name = join ".", $self->name, $chr, 'exon', 'dat';
  my $ex_file = File::Spec->catfile( $index_dir, $ex_name );

  # dbm file
  my $dbm_name = join ".", $self->name, $chr, $self->type, 'kch';
  my $dbm_file = File::Spec->catfile( $index_dir, $dbm_name );

  my $db = Seq::KCManager->new(
    filename => $dbm_file,
    mode     => 'create',
    # bnum => bucket number => 50-400% of expected items in the hash is optimal
    # annotated sites for hg38 is 22727477 (chr1) to 13222 (chrM) with avg of
    # 9060664 and sd of 4925631; thus, took ~1/2 of maximal number of entries
    bnum => 12_000_000,
    msiz => 512_000_000,
  );

  # gene region files - moved to package: seq::build::txtrack
  # my $gene_region_name = join( ".", $self->name, 'gene_region', 'dat' );
  # my $gene_region_file = File::Spec->catfile( $index_dir, $gene_region_name );

  # check if we've already build site range files unless we are forced to overwrite
  unless ( $self->force ) {
    return
      if ( $self->_has_site_range_file($gan_file)
      && $self->_has_site_range_file($ex_file) );
  }

  # 1st line needs to be value that should be added to encoded genome for these sites
  my $gan_fh = $self->get_write_fh($gan_file);
  say {$gan_fh} $self->in_gan_val;
  my $ex_fh = $self->get_write_fh($ex_file);
  say {$ex_fh} $self->in_exon_val;
  # my $gene_region_fh = $self->get_write_fh($gene_region_file);
  # say {$gene_region_fh} $self->in_gene_val;


  for my $gene_href (@$chr_data_aref) {

    my $gene = Seq::Gene->new($gene_href);
    $gene->set_alt_names( %{ $gene_href->{_alt_names} } );

    my ( @fl_sites, @ex_sites ) = ();

    # get intronic flanking site annotations
    my @flank_exon_sites = $gene->all_flanking_sites;
    for my $site (@flank_exon_sites) {
      my $site_href = $site->as_href;
      my $abs_pos   = $site_href->{abs_pos};
      $db->db_put( $abs_pos, $site_href );
      push @fl_sites, $abs_pos;
    }

    # flanking sites need only be written to gan file
    say {$gan_fh} join "\n", @{ $self->_get_range_list( \@fl_sites ) } if @fl_sites;

    # get exon annotations
    my @exon_sites = $gene->all_transcript_sites;
    for my $site (@exon_sites) {
      my $site_href = $site->as_href;
      my $abs_pos   = $site_href->{abs_pos};
      $db->db_put( $abs_pos, $site_href );
      push @ex_sites, $abs_pos;
    }

    # exonic annotations need to be written to both gan and exon files
    # - add a final blank line to the region file; this is a bit of a hack so
    # the c hasher will not crash if there are no entries (after the initial
    # idx mask)
    say {$ex_fh} join "\n",  @{ $self->_get_range_list( \@ex_sites ) }, "";
    say {$gan_fh} join "\n", @{ $self->_get_range_list( \@ex_sites ) }, "";
    # say {$gene_region_fh} join "\t", $gene->transcript_start, $gene->transcript_end;
  }
  $self->_logger->info('finished building gene site db');
}

__PACKAGE__->meta->make_immutable;

1;
