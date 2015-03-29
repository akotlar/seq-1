use 5.10.0;
use strict;
use warnings;

package Seq::Annotate;

# ABSTRACT: Builds a plain text genome used for binary genome creation
# VERSION

use Moose 2;

use Carp qw/ croak /;
use File::Spec;
use MongoDB;
use namespace::autoclean;
use Scalar::Util qw/ reftype /;
use Type::Params qw/ compile /;
use Types::Standard qw/ :types /;
use YAML::XS qw/ LoadFile /;

use Seq::GenomeSizedTrackChar;
use Seq::MongoManager;
use Seq::Site::Annotation;
use Seq::Site::Snp;
use DDP;

extends 'Seq::Assembly';
with 'Seq::Role::IO';

has _genome => (
  is       => 'ro',
  isa      => 'Seq::GenomeSizedTrackChar',
  required => 1,
  lazy     => 1,
  builder  => '_load_genome',
  handles  => ['get_abs_pos']
);

has _genome_score => (
  is      => 'ro',
  isa     => 'ArrayRef[Seq::GenomeSizedTrackChar]',
  traits  => ['Array'],
  handles => { _all_genome_scores => 'elements', },
  lazy    => 1,
  builder => '_load_scores',
);

has _mongo_connection => (
  is      => 'ro',
  isa     => 'Seq::MongoManager',
  lazy    => 1,
  builder => '_build_mongo_connection',
);

has _header => (
  is      => 'ro',
  isa     => 'ArrayRef',
  lazy    => 1,
  builder => '_build_header',
  traits  => ['Array'],
  handles => { all_header => 'elements' },
);

sub _build_mongo_connection {
  state $check = compile(Object);
  my ($self) = $check->(@_);
  return Seq::MongoManager->new(
    {
      default_database => $self->genome_name,
      client_options   => {
        host => $self->mongo_addr,
        port => $self->port,
      },
    }
  );
}

sub _load_genome {
  my $self = shift;
  for my $gst ( $self->all_genome_sized_tracks ) {
    if ( $gst->type eq 'genome' ) {
      return $self->_load_genome_sized_track($gst);
    }
  }
}

sub _load_scores {
  my $self = shift;
  my @score_tracks;
  for my $gst ( $self->all_genome_sized_tracks ) {
    if ( $gst->type eq 'score' ) {
      push @score_tracks, $self->_load_genome_sized_track($gst);
    }
  }
  return \@score_tracks;
}

sub _load_genome_sized_track {
  state $check = compile( Object, Object );
  my ( $self, $gst ) = $check->(@_);

  # index dir
  my $index_dir = File::Spec->canonpath( $self->genome_index_dir );

  # idx file
  my $idx_name = join( ".", $gst->name, $gst->type, 'idx' );
  my $idx_file = File::Spec->catfile( $index_dir, $idx_name );
  my $idx_fh = $self->get_read_fh($idx_file);
  binmode $idx_fh;

  # yml file
  my $yml_name = join( ".", $gst->name, $gst->type, 'yml' );
  my $yml_file = File::Spec->catfile( $index_dir, $yml_name );

  # read genome
  my $seq           = '';
  my $genome_length = -s $idx_file;
  read $idx_fh, $seq, $genome_length;

  # read yml chr offsets
  my $chr_len_href = LoadFile($yml_file);

  my $obj = Seq::GenomeSizedTrackChar->new(
    {
      name          => $gst->name,
      type          => $gst->type,
      genome_chrs   => $self->genome_chrs,
      genome_length => $genome_length,
      chr_len       => $chr_len_href,
      char_seq      => \$seq,
    }
  );
  return $obj;
}

sub get_ref_annotation {
  state $check = compile( Object, Str, Int );
  my ( $self, $chr, $pos ) = $check->(@_);

  my %record;

  my $abs_pos   = $self->get_abs_pos( $chr, $pos );
  my $site_code = $self->_genome->get_base($abs_pos);
  my $base      = $self->_genome->get_idx_base($site_code);
  my $gan       = ( $self->_genome->get_idx_in_gan($site_code) ) ? 1 : 0;
  my $gene      = ( $self->_genome->get_idx_in_gene($site_code) ) ? 1 : 0;
  my $exon      = ( $self->_genome->get_idx_in_exon($site_code) ) ? 1 : 0;
  my $snp       = ( $self->_genome->get_idx_in_snp($site_code) ) ? 1 : 0;

  $record{chr}       = $chr;
  $record{rel_pos}   = $pos;
  $record{abs_pos}   = $abs_pos;
  $record{site_code} = $site_code;
  $record{ref_base}  = $base;

  if ($gene) {
    if ($exon) {
      $record{genomic_annotation_code} = 'Exonic';
    }
    else {
      $record{genomic_annotation_code} = 'Introinc';
    }
  }
  else {
    $record{genomic_annotation_code} = 'Intergenic';
  }

  my ( @gene_data, @snp_data, %conserv_scores );

  for my $gst ( $self->_all_genome_scores ) {
    $record{ $gst->name } = $gst->get_score($abs_pos);
  }

  if ($gan) {
    for my $gene_track ( $self->all_gene_tracks ) {
      push @gene_data,
        $self->_mongo_connection->_mongo_collection( $gene_track->name )
        ->find( { abs_pos => $abs_pos } )->all;
    }
  }

  if ($snp) {
    for my $snp_track ( $self->all_snp_tracks ) {
      push @snp_data,
        $self->_mongo_connection->_mongo_collection( $snp_track->name )
        ->find( { abs_pos => $abs_pos } )->all;
    }
  }

  $record{gene_data} = \@gene_data if @gene_data;
  $record{snp_data}  = \@snp_data  if @snp_data;

  return \%record;
}

# indels will be handled in a separate method
sub get_snp_annotation {
  state $check = compile( Object, Str, Int, Str );
  my ( $self, $chr, $pos, $new_genotype ) = $check->(@_);

  my $ref_site_annotation = $self->get_ref_annotation( $chr, $pos );

  # gene site annotations
  my $gene_aref //= $ref_site_annotation->{gene_data};
  my %gene_site_annotation;
  for my $gene_site (@$gene_aref) {
    $gene_site->{minor_allele} = $new_genotype;
    my $gan = Seq::Site::Annotation->new($gene_site)->as_href_with_NAs;
    for my $attr ( keys %$gan ) {
      if ( exists $gene_site_annotation{$attr} ) {
        if ( $gene_site_annotation{$attr} ne $gan->{$_} ) {
          push @{ $gene_site_annotation{$attr} }, $gan->{$_};
        }
      }
      else {
        $gene_site_annotation{$attr} = $gan->{$attr};
      }
    }
  }

  # snp site annotation
  my $snp_aref //= $ref_site_annotation->{snp_data};
  my %snp_site_annotation;
  for my $snp_site (@$snp_aref) {
    my $san = Seq::Site::Snp->new($snp_site)->as_href_with_NAs;
    for my $attr ( keys %$san ) {
      if ( exists $snp_site_annotation{$attr} ) {
        if ( $snp_site_annotation{$attr} ne $san->{$attr} ) {
          push @{ $snp_site_annotation{$attr} }, $san->{$attr};
        }
      }
      else {
        $snp_site_annotation{$attr} = $san->{$attr};
      }
    }
  }
  my $record = $ref_site_annotation;
  $record->{gene_site_annotation} = \%gene_site_annotation;
  $record->{snp_site_annotation}  = \%snp_site_annotation;

  my $gene_ann = $self->_for_output( \%gene_site_annotation );
  my $snp_ann  = $self->_for_output( \%snp_site_annotation );
  map { $record->{$_} = $gene_ann->{$_} } keys %$gene_ann;
  map { $record->{$_} = $snp_ann->{$_} } keys %$snp_ann;

  my @header = $self->all_header;
  my %hash;
  for my $attr (@header) {
    if ( $record->{$attr} ) {
      $hash{$attr} = $record->{$attr};
    }
    else {
      $hash{$attr} = 'NA';
    }
  }

  return \%hash;
}

sub _for_output {
  my ( $self, $href ) = @_;
  my %hash;

  for my $attrib ( keys %$href ) {
    if ( reftype( $href->{$attrib} ) && reftype( $href->{$attrib} ) eq 'Array' ) {
      $hash{$attrib} = join( ";", @{ $href->{$attrib} } );
    }
    else {
      $hash{$attrib} = $href->{$attrib};
    }
  }
  return \%hash;
}

sub _build_header {
  my $self = shift;

  my ( %gene_features, %snp_features );

  for my $gene_track ( $self->all_gene_tracks ) {
    my @features = $gene_track->all_features;
    map { $gene_features{"alt_names.$_"}++ } @features;
  }
  my @alt_features = map { $_ } keys %gene_features;
  p @alt_features;

  for my $snp_track ( $self->all_snp_tracks ) {
    my @snp_features = $snp_track->all_features;
    map { $snp_features{"snp_features.$_"}++ } @snp_features;
  }
  map { push @alt_features, $_ } keys %snp_features;

  my @features = qw( chr rel_pos ref_base annotation_type codon_number codon_position
    error_code minor_allele new_aa_residue new_codon_seq ref_aa_residue ref_base
    ref_codon_seq site_type strand transcript_id );

  push @features, @alt_features;

  return \@features;
}
__PACKAGE__->meta->make_immutable;

1;
