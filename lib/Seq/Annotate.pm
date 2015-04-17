use 5.10.0;
use strict;
use warnings;

package Seq::Annotate;

# ABSTRACT: Builds a plain text genome used for binary genome creation
# VERSION

use Moose 2;

use Carp qw/ croak /;
use File::Spec;
use namespace::autoclean;
use Scalar::Util qw/ reftype /;
use Type::Params qw/ compile /;
use Types::Standard qw/ :types /;
use YAML::XS qw/ LoadFile /;

use Seq::GenomeSizedTrackChar;
use Seq::MongoManager;
use Seq::BDBManager;
use Seq::Site::Annotation;
use Seq::Site::Snp;

extends 'Seq::Assembly';
with 'Seq::Role::IO', 'MooX::Role::Logger';

has _genome => (
  is       => 'ro',
  isa      => 'Seq::GenomeSizedTrackChar',
  required => 1,
  lazy     => 1,
  builder  => '_load_genome',
  handles  => ['get_abs_pos', 'char_genome_length' ]
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

has bdb_gene => (
  is      => 'ro',
  isa     => 'ArrayRef[Seq::BDBManager]',
  builder => '_build_bdb_gene',
  traits  => ['Array'],
  handles => { _all_bdb_gene => 'elements', },
  lazy    => 1,
);

has bdb_snp => (
  is      => 'ro',
  isa     => 'ArrayRef[Seq::BDBManager]',
  builder => '_build_bdb_snp',
  traits  => ['Array'],
  handles => { _all_bdb_snp => 'elements', },
  lazy    => 1,
);

has bdb_seq => (
  is      => 'ro',
  isa     => 'ArrayRef[Seq::BDBManager]',
  builder => '_build_bdb_tx',
  traits  => ['Array'],
  handles => { _all_bdb_seq => 'elements', },
  lazy    => 1,
);
has _header => (
  is      => 'ro',
  isa     => 'ArrayRef',
  lazy    => 1,
  builder => '_build_header',
  traits  => ['Array'],
  handles => { all_header => 'elements' },
);

sub _get_bdb_file {
  my ( $self, $name ) = @_;
  my $dir = File::Spec->canonpath( $self->genome_index_dir );
  my $file = File::Spec->catfile( $dir, $name );

  croak "ERROR: expected file: '$file' does not exist." unless -f $file;
  croak "ERROR: expected file: '$file' is empty."       unless $file;

  return $file;
}

sub _build_bdb_gene {
  my $self  = shift;
  my @array = ();
  for my $gene_track ( $self->all_gene_tracks ) {
    my $db_name = join ".", $gene_track->name, $gene_track->type, 'db';
    push @array, Seq::BDBManager->new( { filename => $self->_get_bdb_file($db_name), } );
  }
  return \@array;
}

sub _build_bdb_snp {
  my $self  = shift;
  my @array = ();
  for my $snp_track ( $self->all_snp_tracks ) {
    my $db_name = join ".", $snp_track->name, $snp_track->type, 'db';
    push @array, Seq::BDBManager->new( { filename => $self->_get_bdb_file($db_name), } );
  }
  return \@array;
}

sub _build_bdb_tx {
  my $self  = shift;
  my @array = ();
  for my $gene_track ( $self->all_snp_tracks ) {
    my $db_name = join ".", $gene_track->name, $gene_track->type, 'seq', 'db';
    push @array, Seq::BDBManager->new( { filename => $self->_get_bdb_file($db_name), } );
  }
  return \@array;
}

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

sub BUILD {
  my $self = shift;
  $self->_logger->info("genome loaded: " . $self->char_genome_length);
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

  # error check the idx_file
  croak "ERROR: expected file: '$idx_file' does not exist." unless -f $idx_file;
  croak "ERROR: expected file: '$idx_file' is empty."       unless $genome_length;

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
  state $check = compile( Object, Int );
  my ( $self, $abs_pos ) = $check->(@_);

  my %record;

  # my $abs_pos   = $self->get_abs_pos( $chr, $pos );
  my $site_code = $self->_genome->get_base($abs_pos);
  my $base      = $self->_genome->get_idx_base($site_code);
  my $gan       = ( $self->_genome->get_idx_in_gan($site_code) ) ? 1 : 0;
  my $gene      = ( $self->_genome->get_idx_in_gene($site_code) ) ? 1 : 0;
  my $exon      = ( $self->_genome->get_idx_in_exon($site_code) ) ? 1 : 0;
  my $snp       = ( $self->_genome->get_idx_in_snp($site_code) ) ? 1 : 0;

  # $record{chr}       = $chr;
  # $record{rel_pos}   = $pos;
  $record{abs_pos}   = $abs_pos;
  $record{site_code} = $site_code;
  $record{ref_base}  = $base;

  if ($gene) {
    if ($exon) {
      $record{genomic_annotation_code} = 'Exonic';
    }
    else {
      $record{genomic_annotation_code} = 'Intronic';
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
    for my $gene_dbs ( $self->_all_bdb_gene ) {
      push @gene_data, $gene_dbs->db_get($abs_pos);
    }
  }

  if ($snp) {
    for my $snp_dbs ( $self->_all_bdb_snp ) {
      push @snp_data, $snp_dbs->db_get($abs_pos);
    }
  }

  # if ($gan) {
  #   for my $gene_track ( $self->all_gene_tracks ) {
  #     push @gene_data,
  #       $self->_mongo_connection->_mongo_collection( $gene_track->name )
  #       ->find( { abs_pos => $abs_pos } )->all;
  #   }
  # }
  #
  # if ($snp) {
  #   for my $snp_track ( $self->all_snp_tracks ) {
  #     push @snp_data,
  #       $self->_mongo_connection->_mongo_collection( $snp_track->name )
  #       ->find( { abs_pos => $abs_pos } )->all;
  #   }
  # }

  $record{gene_data} = \@gene_data if @gene_data;
  $record{snp_data}  = \@snp_data  if @snp_data;

  return \%record;
}

# indels will be handled in a separate method
sub get_snp_annotation {
  state $check = compile( Object, Int, Str );
  my ( $self, $abs_pos, $new_base ) = $check->(@_);

  my $ref_site_annotation = $self->get_ref_annotation($abs_pos);

  # gene site annotations
  my $gene_aref //= $ref_site_annotation->{gene_data};
  my %gene_site_annotation;
  for my $gene_site (@$gene_aref) {
    $gene_site->{minor_allele} = $new_base;
    my $gan = Seq::Site::Annotation->new($gene_site)->as_href_with_NAs;
    for my $attr ( keys %$gan ) {
      if ( exists $gene_site_annotation{$attr} ) {
        if ( $gene_site_annotation{$attr} ne $gan->{$_} ) {
          $gene_site_annotation{$attr} =
            $self->_join_data( $gene_site_annotation{$attr}, $gan->{$_} );
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
          $snp_site_annotation{$attr} =
            $self->_join_data( $snp_site_annotation{$attr}, $san->{$attr} );
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

  my $gene_ann = $self->_mung_output( \%gene_site_annotation );
  my $snp_ann  = $self->_mung_output( \%snp_site_annotation );
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

sub _join_data {
  my ( $self, $old_val, $new_val ) = @_;
  my $type = reftype($old_val);
  if ($type) {
    if ( $type eq 'Array' ) {
      unless ( grep { /$new_val/ } @$old_val ) {
        push @{$old_val}, $new_val;
        return $old_val;
      }
    }
  }
  else {
    my @new_array;
    push @new_array, $old_val, $new_val;
    return \@new_array;
  }
}

sub _mung_output {
  my ( $self, $href ) = @_;
  my %hash;
  for my $attrib ( keys %$href ) {
    my $ref = reftype( $href->{$attrib} );
    if ( $ref && $ref eq 'Array' ) {
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

  for my $snp_track ( $self->all_snp_tracks ) {
    my @snp_features = $snp_track->all_features;

    # this is a total hack got allow me to calcuate a single MAF for the snp
    # that's not already a value we retrieve and, therefore, doesn't fit in the
    # framework well
    push @snp_features, 'maf';
    map { $snp_features{"snp_feature.$_"}++ } @snp_features;
  }
  map { push @alt_features, $_ } keys %snp_features;

  my @features = qw/ chr pos ref_base genomic_annotation_code annotation_type
    codon_number codon_position error_code minor_allele new_aa_residue new_codon_seq
    ref_aa_residue ref_base ref_codon_seq site_type strand transcript_id /;

  push @features, @alt_features;

  return \@features;
}

sub annotate_dels {
  state $check = compile( Object, HashRef );
  my ( $self, $sites_href ) = $check->(@_);
  my ( @annotations, @contiguous_sites, $last_abs_pos );

  # $site_href is defined as %site{ abs_pos } = [ chr, pos ]

  for my $abs_pos ( sort { $a <=> $b } keys %$sites_href ) {
    if ( $last_abs_pos + 1 == $abs_pos ) {
      push @contiguous_sites, $abs_pos;
      $last_abs_pos = $abs_pos;
    }
    else {

      # annotate site
      my $record = $self->_annotate_del_sites( \@contiguous_sites );

      # arbitrarily assign the 1st del site as the one we'll report
      ( $record->{chr}, $record->{pos} ) = @{ $sites_href->{ $contiguous_sites[0] } };

      # save annotations
      push @annotations, $record;
      @contiguous_sites = ();
    }
  }
  return \@annotations;
}

# data for tx_sites:
# hash{ abs_pos } = (
# coding_start => $gene->coding_start,
# coding_end => $gene->coding_end,
# exon_starts => $gene->exon_starts,
# exon_ends => $gene->exon_ends,
# transcript_start => $gene->transcript_start,
# transcript_end => $gene->transcript_end,
# transcript_id => $gene->transcript_id,
# transcript_seq => $gene->transcript_seq,
# transcript_annotation => $gene->transcript_annotation,
# transcript_abs_position => $gene->transcript_abs_position,
# peptide_seq => $gene->peptide,
# );

sub _annotate_del_sites {
  state $check = compile( Object, ArrayRef );
  my ( $self, $site_aref ) = $check->(@_);
  my ( @tx_hrefs, @records );

  for my $abs_pos (@$site_aref) {
    # get a seq::site::gene record munged with seq::site::snp

    my $record = $self->get_ref_annotation($abs_pos);

    for my $gene_data ( @{ $record->{gene_data} } ) {
      my $tx_id = $gene_data->{transcript_id};

      for my $bdb_seq ( $self->_all_bdb_seq ) {
        my $tx_href = $bdb_seq->db_get($tx_id);
        if ( defined $tx_href ) {
          push @tx_hrefs, $tx_href;
        }
      }
    }
    for my $tx_href (@tx_hrefs) {
      # substring...
    }
  }
}

__PACKAGE__->meta->make_immutable;

1;
