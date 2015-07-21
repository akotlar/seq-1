use 5.10.0;
use strict;
use warnings;

package Seq::Annotate;

# ABSTRACT: Annotates sites of a given genome assembly.
# VERSION

=head1 DESCRIPTION Seq::Annotate

  Contains helper functions for genome annotation of a given genome assembly.

Used in:

=begin :list
* bin/annotate_ref_site.pl
* bin/read_genome_with_dbs.pl
* @class Seq::Config::GenomeSizedTrack
* @class Seq::Site::Annotation
* @class Seq
  The class which gets called to complete the annotation. Used in:

  =begin :list
  * bin/annotate_snpfile.pl
    Basic command line annotator function. TODO: superceede with Interface.pm
  * bin/annotate_snpfile_socket_server.pl
    Basic socket/multi-core annotator (one annotation instance per core, non-blocking). TODO: superceede w/ Interface.pm
  * bin/redis_queue_server.pl
    Multi-core/process annotation job listener. Spawns Seq jobs
  =end :list
=end :list

Extended in: None

Extends: @class Seq::Assembly

Uses:
=for :list
* @class Seq::GenomeSizedTrackChar
* @class Seq::KCManager
* @class Seq::Site::Annotation
* @class Seq::Site::Snp
* @role Seq::Role::IO

TODO: extend this description
=cut

use Moose 2;
use Carp qw/ croak /;
use Path::Tiny qw/ path /;
use namespace::autoclean;
use Scalar::Util qw/ reftype /;
use Type::Params qw/ compile /;
use Types::Standard qw/ :types /;
use YAML::XS qw/ LoadFile /;

use DDP; # for debugging

use Seq::GenomeSizedTrackChar;
use Seq::KCManager;
use Seq::Site::Annotation;
use Seq::Site::Snp;

extends 'Seq::Assembly';
with 'Seq::Role::IO';

# TODO: remove `genome_index_dir` after testing; NOTE: `genome_index_dir` is
#       already defined in Seq::Assembly, which Seq::Annotate extends.
# has genome_index_dir => (
#   is       => 'ro',
#   isa      => 'Str',
#   required => 1
# );

=property @private {Seq::GenomeSizedTrackChar<Str>} _genome

  Binary-encoded genome string.

@see @class Seq::GenomeSizedTrackChar
=cut

has _genome => (
  is       => 'ro',
  isa      => 'Seq::GenomeSizedTrackChar',
  required => 1,
  lazy     => 1,
  builder  => '_load_genome',
  handles  => [
    'get_abs_pos',    'char_genome_length', 'genome_length',   'get_base',
    'get_idx_base',   'get_idx_in_gan',     'get_idx_in_gene', 'get_idx_in_exon',
    'get_idx_in_snp', 'chr_len',            'next_chr',
  ]
);

sub _load_genome {
  my $self = shift;

  for my $gst ( $self->all_genome_sized_tracks ) {
    if ( $gst->type eq 'genome' ) {
      return $self->_load_genome_sized_track($gst);
    }
  }
}

has _genome_scores => (
  is      => 'ro',
  isa     => 'ArrayRef[Maybe[Seq::GenomeSizedTrackChar]]',
  traits  => ['Array'],
  handles => {
    _all_genome_scores  => 'elements',
    count_genome_scores => 'count',
  },
  lazy    => 1,
  builder => '_load_scores',
);

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
  my ( $self, $gst ) = @_;

  # index dir
  my $index_dir = $self->genome_index_dir;

  # check files exist and are not empty
  my $msg_aref = $self->_check_genome_sized_files(
    [ $gst->genome_bin_file, $gst->genome_offset_file ] );

  # if $msg_aref has data then we had some errors; print and halt
  if (scalar @$msg_aref > 0) {
    $self->_logger->error( join( "\n", @$msg_aref ) );
    croak join( "\n", @$msg_aref );
  }

  my $idx_file = $gst->genome_bin_file;
  my $idx_fh   = $self->get_read_fh($idx_file);
  binmode $idx_fh;

  # read genome
  my $seq           = '';
  my $genome_length = -s $idx_file;
  read $idx_fh, $seq, $genome_length;

  # read yml chr offsets
  my $yml_file     = $gst->genome_offset_file;
  my $chr_len_href = LoadFile($yml_file);

  my $obj = Seq::GenomeSizedTrackChar->new(
    {
      name          => $gst->name,
      type          => $gst->type,
      genome_chrs   => $gst->genome_chrs,
      genome_length => $genome_length,
      chr_len       => $chr_len_href,
      char_seq      => \$seq,
    }
  );

  my $msg = sprintf( "read genome-sized track '%s' of length %d from file: %s",
    $gst->name, $genome_length, $idx_file );
  $self->_logger->info($msg);
  say $msg if $self->debug;

  return $obj;
}

has _genome_cadd => (
  is      => 'ro',
  isa     => 'ArrayRef[Maybe[Seq::GenomeSizedTrackChar]]',
  traits  => ['Array'],
  handles => {
    _get_cadd_track   => 'get',
    count_cadd_scores => 'count',
  },
  lazy    => 1,
  builder => '_load_cadd',
);

sub _load_cadd {
  my $self = shift;

  for my $gst ( $self->all_genome_sized_tracks ) {
    if ( $gst->type eq 'cadd' ) {
      $self->set_cadd;
      return $self->_load_cadd_score($gst);
    }
  }
  # return an empty arrayref to satisfy the type if we don't have a cadd track
  return [];
}

sub _load_cadd_score {
  my ( $self, $gst ) = @_;

  my @cadd_scores;

  # index dir
  my $index_dir = $self->genome_index_dir;

  for my $i ( 0 .. 2 ) {

    # idx file
    my $idx_file = $gst->cadd_idx_file($i);

    # check files exist and are not empty
    my $msg_aref = $self->_check_genome_sized_files( [$idx_file] );

    # if $msg_aref has data then we had some errors; print and halt
    if (scalar @$msg_aref > 0) {
      $self->_logger->error( join( "\n", @$msg_aref ) );
      croak join( "\n", @$msg_aref );
    }

    # read the file
    my $idx_fh = $self->get_read_fh($idx_file);
    binmode $idx_fh;

    # read genome
    my $seq           = '';
    my $genome_length = -s $idx_file;
    read $idx_fh, $seq, $genome_length;
    
    # read yml chr offsets
    my $yml_file     = $gst->genome_offset_file;
    my $chr_len_href = LoadFile($yml_file);

    my $obj = Seq::GenomeSizedTrackChar->new(
      {
        name          => $gst->name,
        type          => $gst->type,
        genome_chrs   => $gst->genome_chrs,
        genome_length => $genome_length,
        chr_len       => $chr_len_href,
        char_seq      => \$seq,
      }
    );
    push @cadd_scores, $obj;
    my $msg =
      sprintf( "read cadd track file '%s' of length %d", $idx_file, $genome_length );
    $self->_logger->info($msg);
    say $msg if $self->debug;
  }
  # tell the package we loaded some cadd scores
  $self->set_cadd;
  return \@cadd_scores;
}

sub _check_genome_sized_files {
  my ( $self, $files_aref ) = @_;

  my @msg;

  for my $file (@$files_aref) {
    if ( !-f $file ) {
      push @msg, sprintf( "cannot find file: %s", $file );
    }
    else {
      if ( !-s $file ) {
        push @msg, sprintf( "file '%s' is zero-sized", $file );
      }
    }
  }
  return \@msg;
}

sub get_cadd_score {
  my ( $self, $abs_pos, $ref, $allele ) = @_;

  my $key = join ":", $ref, $allele;
  my $i = $self->get_cadd_index($key);
  if ( $self->debug ) {
    say "Cadd score key:";
    p $key;
    say "Cadd score index:";
    p $i;
  }
  if ( defined $i ) {
    my $cadd_track = $self->_get_cadd_track($i);
    return $cadd_track->get_score($abs_pos);
  }
  else {
    return 'NA';
  }
}

=property @private {HashRef} _cadd_lookup

  Defines delegate @method @public get_cadd_index

=cut

=method get_cadd_index

  Delegate on behalf of @param _cadd_lookup.

  my $key = join ":", $ref_base, $base_in_sample;
  $self->get_cadd_index($key)

  see L<Moose::Meta::Attribute::Native::Trait::Hash>

=cut

has _cadd_lookup => (
  is      => 'ro',
  isa     => 'HashRef',
  traits  => ['Hash'],
  handles => { get_cadd_index => 'get', },
  lazy    => 1,
  builder => '_build_cadd_lookup',
);

sub _build_cadd_lookup {
  my $self = shift;

  my %cadd_lu;
  my @ref_bases   = qw/ A C G T/;
  my @input_bases = qw/ A C G T/;
  for my $ref (@ref_bases) {
    my $i = 0;
    for my $input (@input_bases) {
      if ( $ref ne $input ) {
        my $key = join ":", $ref, $input;
        $cadd_lu{$key} = $i;
        $i++;
      }
    }
  }
  \%cadd_lu;
}

=property @public {ArrayRef<ArrayRef<Seq::KCManager>>} _cadd_lookup

  Defines delegate @method @private _all_dbm_gene

=cut

has dbm_gene => (
  is      => 'ro',
  isa     => 'ArrayRef[ArrayRef[Maybe[Seq::KCManager]]]',
  builder => '_build_dbm_gene',
  traits  => ['Array'],
  handles => { _all_dbm_gene => 'elements', },
  lazy    => 1,
);

has dbm_snp => (
  is      => 'ro',
  isa     => 'ArrayRef[ArrayRef[Maybe[Seq::KCManager]]]',
  builder => '_build_dbm_snp',
  traits  => ['Array'],
  handles => { _all_dbm_snp => 'elements', },
  lazy    => 1,
);

has dbm_tx => (
  is      => 'ro',
  isa     => 'ArrayRef[Seq::KCManager]',
  builder => '_build_dbm_tx',
  traits  => ['Array'],
  handles => { _all_dbm_tx => 'elements', },
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

=property @public {Bool} has_cadd_track

  Records whether or not we have a cadd_track.

=cut

=method set_cadd

  Delegates the Moose "set" method, which Sets the value to 1 and returns 1.

=cut

=method set_cadd

  Delegates the Moose "set" method, which Sets the value of has_cadd_track to 1
  and returns 1.

=cut

=method unset_cadd

  Delegates the Moose "unset" method, which Sets the value of has_cadd_track to
  0 and returns 0.

=cut

has has_cadd_track => (
  is      => 'rw',
  isa     => 'Bool',
  traits  => ['Bool'],
  default => 0,
  handles => {
    unset_cadd => 'unset',
    set_cadd   => 'set',
  }
);

sub _build_dbm_array {
  my ( $self, $track ) = @_;
  my @array;
  for my $chr ( $track->all_genome_chrs ) {
    my $dbm = $track->get_kch_file($chr);
    if ( -f $dbm ) {
      push @array, Seq::KCManager->new( { filename => $dbm, mode => 'read', } );
    }
    else {
      push @array, undef;
    }
  }
  return \@array;
}

sub _build_dbm_snp {
  my $self = shift;
  my @array;
  for my $snp_track ( $self->all_snp_tracks ) {
    push @array, $self->_build_dbm_array( $snp_track );
  }
  return \@array;
}

sub _build_dbm_gene {
  my $self = shift;
  my @array;
  for my $gene_track ( $self->all_gene_tracks ) {
    push @array, $self->_build_dbm_array( $gene_track );
  }
  return \@array;
}

sub _build_dbm_tx {
  my $self = shift;
  my @array;
  for my $gene_track ( $self->all_gene_tracks ) {
    my $dbm = $gene_track->get_kch_file( 'genome', 'tx' );
    if ( -f $dbm ) {
      push @array, Seq::KCManager->new( { filename => $dbm, mode => 'read', } );
    }
    else {
      push @array, undef;
    }
  }
  return \@array;
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

  my @features =
    qw/ chr pos ref_base type alleles allele_counts genomic_annotation_code annotation_type
    codon_number codon_position error_code minor_allele new_aa_residue new_codon_seq
    ref_aa_residue ref_base ref_codon_seq site_type strand transcript_id snp_id /;

  # add genome score track names
  for my $gs ( $self->_all_genome_scores ) {
    push @features, $gs->name;
  }

  push @features, @alt_features;
  push @features, 'cadd' if $self->has_cadd_track;

  return \@features;
}

sub BUILD {
  my $self = shift;
  p $self if $self->debug;

  my $msg = sprintf( "Loaded genome of size: %d", $self->genome_length );
  say $msg if $self->debug;
  $self->_logger->info($msg);

  $msg =
    sprintf( "Loaded %d genome score track(s)", $self->count_genome_scores );
  say $msg if $self->debug;
  $self->_logger->info($msg);

  $msg = sprintf( "Loaded %d cadd scores", $self->count_cadd_scores );
  say $msg if $self->debug;
  $self->_logger->info($msg);

  for my $dbm_aref ( $self->_all_dbm_snp, $self->_all_dbm_gene ) {
    my @chrs = $self->all_genome_chrs;
    for (my $i = 0; $i < @chrs; $i++) {
      my $dbm = ( $dbm_aref->[$i] ) ? $dbm_aref->[$i]->filename : 'NA';
      my $msg = sprintf( "Loaded dbm: %s for chr: %s", $dbm, $chrs[$i] );
      say $msg if $self->debug;
      $self->_logger->info($msg);
    }
  }
  for my $dbm_aref ( $self->_all_dbm_tx ) {
    my $dbm = ( $dbm_aref ) ? $dbm_aref->filename : 'NA';
    my $msg = sprintf( "Loaded dbm: %s for genome", $dbm );
    say $msg if $self->debug;
    $self->_logger->info($msg);
  }
}

sub get_ref_annotation {
  state $check = compile( Object, Int, Int );
  my ( $self, $chr_index, $abs_pos ) = $check->(@_);

  my %record;

  my $site_code = $self->get_base($abs_pos);
  my $base      = $self->get_idx_base($site_code);
  my $gan       = ( $self->get_idx_in_gan($site_code) ) ? 1 : 0;
  my $gene      = ( $self->get_idx_in_gene($site_code) ) ? 1 : 0;
  my $exon      = ( $self->get_idx_in_exon($site_code) ) ? 1 : 0;
  my $snp       = ( $self->get_idx_in_snp($site_code) ) ? 1 : 0;

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

  # get scores at site
  for my $gs ( $self->_all_genome_scores ) {
    $record{ $gs->name } = $gs->get_score($abs_pos);
  }

  # get gene annotations at site
  if ($gan) {
    for my $gene_dbs ( $self->_all_dbm_gene ) {
      my $kch = $gene_dbs->[$chr_index];
      p $kch if $self->debug;

      # if there's no file for the track then it will be undef
      next unless defined $kch;
      my $rec = $kch->db_get($abs_pos);
      if ( $self->debug ) {
        print "\n\nThis is rec:\n\n";
        p $rec;
      }
      push @gene_data, @$rec if defined $rec;
    }
    $record{gene_data} = \@gene_data;
  }

  # get snp annotations at site
  if ($snp) {
    for my $snp_dbs ( $self->_all_dbm_snp ) {
      my $kch = $snp_dbs->[$chr_index];

      # if there's no file for the track then it will be undef
      next unless defined $kch;
      my $rec = $kch->db_get($abs_pos);
      if ( $self->debug ) {
        p $kch;
        p $rec;
      }
      push @snp_data, @$rec if defined $rec;
    }
    $record{snp_data} = \@snp_data;
  }

  return \%record;
}

# annotate a snp site
sub get_snp_annotation {
  state $check = compile( Object, Int, Int, Str, Str );
  my ( $self, $chr_index, $abs_pos, $ref_base, $new_base ) = $check->(@_);

  say "about to get ref annotation: $abs_pos" if $self->debug;

  my $ref_site_annotation = $self->get_ref_annotation( $chr_index, $abs_pos );

  if ( $ref_site_annotation->{ref_base} ne $ref_base ) {
    my $err_msg = sprintf(
      "ERROR: At abs pos '%d', input reference base (%s) does not agree stored reference base (%s)",
      $abs_pos, $ref_base, $ref_site_annotation->{ref_base} );
    say $err_msg;
    $self->_logger->error($err_msg);
    exit(1);
  }

  p $ref_site_annotation if $self->debug;

  # gene site annotations
  my $gene_aref = $ref_site_annotation->{gene_data};
  my $gene_site_ann_href;
  for my $gene_site (@$gene_aref) {

    # get data; need to add new base to href to create the obj with wanted
    #   data, like proper AA substitution
    $gene_site->{minor_allele} = $new_base;

    # TODO: optimize this function by passing ref $gene_site, $self->name instead of checking type
    my $gan = Seq::Site::Annotation->new($gene_site)->as_href_with_NAs;

    # merge data
    $gene_site_ann_href = $self->_join_href( $gene_site_ann_href, $gan );
  }

  # snp site annotation
  my $snp_aref = $ref_site_annotation->{snp_data};
  my $snp_site_ann_href;
  for my $snp_site (@$snp_aref) {

    # get data
    # TODO: optimize this function by passing ref $gene_site, $self->name instead of checking type
    my $san = Seq::Site::Snp->new($snp_site)->as_href_with_NAs;

    # merge data
    $snp_site_ann_href = $self->_join_href( $snp_site_ann_href, $san );
  }

  # original annotation and merged annotations
  my $record = $ref_site_annotation;
  my $merged_ann = $self->_join_href( $gene_site_ann_href, $snp_site_ann_href );

  my %hash;
  my @header = $self->all_header;

  # add cadd score
  if ( $self->has_cadd_track ) {
    $record->{cadd} =
      $self->get_cadd_score( $abs_pos, $ref_site_annotation->{ref_base}, $new_base );
  }
  else {
    say "We don't have a cadd track" if $self->debug;
  }

  for my $attr (@header) {
    if ( defined $record->{$attr} ) {
      $hash{$attr} = $record->{$attr};
    }
    elsif ( defined $merged_ann->{$attr} ) {
      $hash{$attr} = $merged_ann->{$attr};
    }
    else {
      $hash{$attr} = 'NA';
    }
  }
  p %hash if $self->debug;
  return \%hash;
}

#
#  this method joins together data; preserving the sequential order
#
sub _join_href {
  my ( $self, $old_href, $new_href ) = @_;

  my %attrs = map { $_ => 1 } ( keys %$old_href, keys %$new_href );
  my %merge;

  for my $attr ( keys %attrs ) {
    my $old_val = $old_href->{$attr};
    my $new_val = $new_href->{$attr};
    if ( defined $old_val and defined $new_val ) {
      if ( $old_val eq $new_val ) {
        $merge{$attr} = join ";", $old_val, $new_val;
      }
      else {
        my @old_vals = split /\;/, $old_val;
        push @old_vals, $new_val;
        $merge{$attr} = join ";", @old_vals;
      }
    }
    elsif ( defined $old_val ) {
      $merge{$attr} = $old_val;
    }
    elsif ( defined $new_val ) {
      $merge{$attr} = $new_val;
    }
  }
  return \%merge;
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

      for my $dbm_seq ( $self->_all_dbm_seq ) {
        my $tx_href = $dbm_seq->db_get($tx_id);
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
