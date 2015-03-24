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
use Type::Params qw/ compile /;
use Types::Standard qw/ :types /;
use YAML::XS qw/ LoadFile /;

use Seq::GenomeSizedTrackChar;
use Seq::MongoManager;

extends 'Seq::Assembly';
with 'Seq::Role::IO';

has _genome => (
  is       => 'ro',
  isa      => 'Seq::GenomeSizedTrackChar',
  required => 1,
  lazy     => 1,
  builder  => '_load_genome',
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

sub annotate_site {
  state $check = compile( Object, Str, Int );
  my ( $self, $chr, $pos ) = $check->(@_);

  my %record;

  my $abs_pos   = $self->_genome->get_abs_pos( $chr, $pos );
  my $site_code = $self->_genome->get_base($abs_pos);
  my $base      = $self->_genome->get_idx_base($site_code);
  my $gan       = ( $self->_genome->get_idx_in_gan($site_code) ) ? 1 : 0;
  my $gene      = ( $self->_genome->get_idx_in_gene($site_code) ) ? 1 : 0;
  my $exon      = ( $self->_genome->get_idx_in_exon($site_code) ) ? 1 : 0;
  my $snp       = ( $self->_genome->get_idx_in_snp($site_code) ) ? 1 : 0;

  $record{abs_pos}   = $abs_pos;
  $record{site_code} = $site_code;
  $record{base}      = $base;
  $record{gan}       = $gan;
  $record{gene}      = $gene;
  $record{exon}      = $exon;
  $record{snp}       = $snp;

  my ( @gene_data, @snp_data, %conserv_scores );

  for my $gst ( $self->_all_genome_scores ) {
    $conserv_scores{ $gst->name } = $gst->get_score($abs_pos);
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

  $record{conserv_scores} = \%conserv_scores if %conserv_scores;
  $record{gan_data}       = \@gene_data      if @gene_data;
  $record{snp_data}       = \@snp_data       if @snp_data;

  return \%record;
}

__PACKAGE__->meta->make_immutable;

1;
