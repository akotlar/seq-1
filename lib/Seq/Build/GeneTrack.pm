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

extends 'Seq::Build::SparseTrack';
with 'Seq::Role::IO';

sub build_gene_db {
  my $self = shift;

  $self->_logger->info('starting to build gene site db');

  # input
  my $local_dir  = File::Spec->canonpath( $self->local_dir );
  my $local_file = File::Spec->catfile( $local_dir, $self->local_file );
  my $in_fh      = $self->get_read_fh($local_file);

  # output
  my $index_dir = File::Spec->canonpath( $self->genome_index_dir );
  make_path($index_dir) unless -f $index_dir;

  # flanking site range file
  my $gan_name = join( ".", $self->name, 'gan', 'dat' );
  my $gan_file = File::Spec->catfile( $index_dir, $gan_name );

  # exon site range file
  my $ex_name = join( ".", $self->name, 'exon', 'dat' );
  my $ex_file = File::Spec->catfile( $index_dir, $ex_name );

  # gene region files
  # my $gene_region_name = join( ".", $self->name, 'gene_region', 'dat' );
  # my $gene_region_file = File::Spec->catfile( $index_dir, $gene_region_name );

  # check if we've already build site range files
  return
    if ( $self->_has_site_range_file($gan_file)
    && $self->_has_site_range_file($ex_file) );

  # 1st line needs to be value that should be added to encoded genome for these sites
  my $gan_fh = $self->get_write_fh($gan_file);
  say {$gan_fh} $self->in_gan_val;
  my $ex_fh = $self->get_write_fh($ex_file);
  say {$ex_fh} $self->in_exon_val;
  # my $gene_region_fh = $self->get_write_fh($gene_region_file);
  # say {$gene_region_fh} $self->in_gene_val;

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
    #   - the basic problem is that the type constraint on alt_names wants
    #   the hash to contain strings; without the ($data{$_}) ? $data{$_} : 'NA'
    #   there were some keys with blank values
    #   - this feels like a hack to accomidate the type constraint on alt_names
    #   attributes and will increase the db size; may just drop the keys without
    #   data in the future but it's running now so will hold off for the time
    #   being.
    my %alt_names = map { $_ => ( $data{$_} ) ? $data{$_} : 'NA' if exists $data{$_} }
      ( $self->all_features );

    my $gene = Seq::Gene->new( \%gene_data );
    $gene->set_alt_names(%alt_names);

    my ( @fl_sites, @ex_sites ) = ();

    # get intronic flanking site annotations
    my @flank_exon_sites = $gene->all_flanking_sites;
    for my $site (@flank_exon_sites) {
      my $site_href = $site->as_href;
      my $abs_pos   = $site_href->{abs_pos};
      $self->db_put( $abs_pos, $site_href );
      push @fl_sites, $abs_pos;
    }

    # flanking sites need only be written to gan file
    say {$gan_fh} join "\n", @{ $self->_get_range_list( \@fl_sites ) } if @fl_sites;

    # get exon annotations
    my @exon_sites = $gene->all_transcript_sites;
    for my $site (@exon_sites) {
      my $site_href = $site->as_href;
      my $abs_pos   = $site_href->{abs_pos};
      $self->db_put( $abs_pos, $site_href );
      push @ex_sites, $abs_pos;
    }

    # exonic annotations need to be written to both gan and exon files
    say {$ex_fh} join "\n",          @{ $self->_get_range_list( \@ex_sites ) };
    say {$gan_fh} join "\n",         @{ $self->_get_range_list( \@ex_sites ) };
    # say {$gene_region_fh} join "\t", $gene->transcript_start, $gene->transcript_end;
  }
  $self->_logger->info('finished building gene site db');
}

__PACKAGE__->meta->make_immutable;

1;
