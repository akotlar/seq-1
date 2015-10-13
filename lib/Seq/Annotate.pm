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

use DDP;                   # for debugging
use Data::Dump qw( dump ); # for debugging
use Cpanel::JSON::XS;

use Seq::GenomeSizedTrackChar;
use Seq::KCManager;
use Seq::Site::Annotation;
use Seq::Site::Snp;
use Seq::Annotate::Indel;
use Seq::Annotate::Snp;


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
  if ( scalar @$msg_aref > 0 ) {
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
    if ( scalar @$msg_aref > 0 ) {
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
    push @array, $self->_build_dbm_array($snp_track);
  }
  return \@array;
}

sub _build_dbm_gene {
  my $self = shift;
  my @array;
  for my $gene_track ( $self->all_gene_tracks ) {
    push @array, $self->_build_dbm_array($gene_track);
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
  
  my @features;
  # make Seq::Site::Annotation and Seq::Site::Snp object, and use those to 
  # make a Seq::Annotation::Snp object; gather all attributes from those
  # objects, which constitutes the basic header; the remaining pieces will
  # be gathered from the 'scores' and 'gene' and 'snp' tracks that might
  # have various alternative data, depending on the assembly

  # make Seq::Site::Annotation object and add attrs to @features
  my $ann_href = {
      abs_pos => 10653420,
      alt_names => {
        protAcc => 'NM_017766',
        mRNA => 'NM_017766',
        geneSymbol => 'CASZ1',
        spID => 'Q86V15',
        rfamAcc => 'NA',
        description => 'Test',
        kgID => 'uc001arp.3',
        spDisplayID => 'CASZ1_HUMAN',
        refseq => 'NM_017766',
      },
      codon_position => 1,
      codon_number => 879,
      minor_allele => 'T',
      ref_base => 'G',
      ref_codon_seq => 'AGG',
      ref_aa_residue => 'R',
      site_type => 'Coding',
      strand => '-',
      transcript_id => 'NM_017766',
  };
  my $ann_obj = Seq::Site::Annotation->new($ann_href);
  my $ann_attr_href = $ann_obj->header_attr;

  # make Seq::Site:Snp object and add attrs to @features
  my $snp_href = {
    "abs_pos" => 10653420,
    "ref_base" => "G",
    "snp_id" => "rs123",
    "snp_feature" => {
      "alleleNs" => "NA",
      "refUCSC" => "T",
      "alleles" => "NA",
      "observed" => "G/T",
      "name" => "rs123",
      "alleleFreqs" => "NA",
      "strand" => "+",
      "func" => "fake",
      "alleleFreqCount" => 0,
    },
  };
  my $snp_obj = Seq::Site::Snp->new($snp_href);
  my $snp_attr_href = $snp_obj->header_attr;

  my $annotation_snp_href = {
    chr => 'chr1',
    pos => 10653420,
    var_allele => 'T',
    allele_count => 2,
    alleles => 'G,T',
    abs_pos => 10653420,
    var_type => 'SNP',
    ref_base => 'G',
    het_ids => '',
    hom_ids => 'Sample_3',
    genomic_type => 'Exonic',
    scores => {
      cadd => 10,
      phyloP => 3,
      phasCons => 0.9,
    },
    gene_data => [ $ann_obj ],
    snp_data => [ $snp_obj ],
  };
  my $ann_snp_obj = Seq::Annotate::Snp->new( $annotation_snp_href );
  my $ann_snp_attr_href = $ann_snp_obj->header_attr;

  my %obj_attrs = map { $_ => 1 } (keys %$ann_snp_attr_href, keys %$ann_attr_href, keys %$snp_attr_href);

  # some features are always expected
  @features = qw/ chr pos var_type alleles allele_count genomic_type site_type annotation_type ref_base
    minor_allele /;
  my %exp_features = map { $_ => 1 } @features;

  for my $feature ( sort keys %obj_attrs ) {
    if (!exists $exp_features{$feature} ) {
      push @features, $feature;
    }
  }

  # add genome score track names to @features
  for my $gs ( $self->_all_genome_scores ) {
    push @features, $gs->name;
  }
  push @features, 'cadd' if $self->has_cadd_track;
  
  # determine alt features and add them to @features
  my (@alt_features, %gene_features, %snp_features );

  for my $gene_track ( $self->all_gene_tracks ) {
    my @gene_features = $gene_track->all_features;
    map { $gene_features{"alt_names.$_"}++ } @gene_features;
  }
  push @alt_features, $_ for sort keys %gene_features;

  for my $snp_track ( $self->all_snp_tracks ) {
    my @snp_features = $snp_track->all_features;

    # this is a hack to allow me to calcuate a single MAF for the snp
    # that's not already a value we retrieve and, therefore, doesn't fit in the
    # framework well
    push @snp_features, 'maf';
    map { $snp_features{"snp_feature.$_"}++ } @snp_features;
  }
  push @alt_features, $_ for sort keys %snp_features;

  # add alt features
  push @features, @alt_features;

  return \@features;
}

sub BUILD {
  my $self = shift;
  p $self if $self->debug;

  my $msg = sprintf( "Loaded genome of size: %d", $self->genome_length );
  say $msg if $self->debug;
  $self->_logger->info($msg);

  $msg = sprintf( "Loaded %d genome score track(s)", $self->count_genome_scores );
  say $msg if $self->debug;
  $self->_logger->info($msg);

  $msg = sprintf( "Loaded %d cadd scores", $self->count_cadd_scores );
  say $msg if $self->debug;
  $self->_logger->info($msg);

  for my $dbm_aref ( $self->_all_dbm_snp, $self->_all_dbm_gene ) {
    my @chrs = $self->all_genome_chrs;
    for ( my $i = 0; $i < @chrs; $i++ ) {
      my $dbm = ( $dbm_aref->[$i] ) ? $dbm_aref->[$i]->filename : 'NA';
      my $msg = sprintf( "Loaded dbm: %s for chr: %s", $dbm, $chrs[$i] );
      say $msg if $self->debug;
      $self->_logger->info($msg);
    }
  }
  for my $dbm_aref ( $self->_all_dbm_tx ) {
    my $dbm = ($dbm_aref) ? $dbm_aref->filename : 'NA';
    my $msg = sprintf( "Loaded dbm: %s for genome", $dbm );
    say $msg if $self->debug;
    $self->_logger->info($msg);
  }
}

# annotate_snp_site returns a hash reference of the annotation data for a 
# given position and variant alleles
sub annotate_snp_site {
  my ( $self, $chr, $chr_index, $rel_pos, $abs_pos, $ref_allele, $var_type, $all_allele_str,
    $allele_count, $het_ids, $hom_ids) = @_;

  my %record;

  my $site_code = $self->get_base($abs_pos);
  my $base      = $self->get_idx_base($site_code);
  my $gan       = ( $self->get_idx_in_gan($site_code) ) ? 1 : 0;
  my $gene      = ( $self->get_idx_in_gene($site_code) ) ? 1 : 0;
  my $exon      = ( $self->get_idx_in_exon($site_code) ) ? 1 : 0;
  my $snp       = ( $self->get_idx_in_snp($site_code) ) ? 1 : 0;
  my @var_alleles = grep { !/$base/ } (split /\,/, $all_allele_str);

  if ($base ne $ref_allele) {
    my $msg = sprintf("Error: Discordant ref base at site %s:%d (abs_pos: %d); obs: '%s', got: '%s'",
      $chr, $rel_pos, $abs_pos, $base, $ref_allele);
    $self->_logger->warn($msg);
    $record{warning} = $msg;
  }

  $record{chr} = $chr;
  $record{pos} = $rel_pos;
  $record{var_allele} = join ",", @var_alleles;
  $record{allele_count} = $allele_count;
  $record{alleles} = $all_allele_str;
  $record{abs_pos}   = $abs_pos;
  $record{var_type} = $var_type;
  $record{ref_base}  = $base;
  $record{het_ids} = $het_ids;
  $record{hom_ids} = $hom_ids;

  if ($gene) {
    if ($exon) {
      $record{genomic_type} = 'Exonic';
    }
    else {
      $record{genomic_type} = 'Intronic';
    }
  }
  else {
    $record{genomic_type} = 'Intergenic';
  }

  # get scores at site
  for my $gs ( $self->_all_genome_scores ) {
    $record{scores}{ $gs->name } = $gs->get_score($abs_pos);
  }

  # add cadd score
  if ( $self->has_cadd_track ) {
    for my $var_allele ( @var_alleles) {
      $record{scores}{cadd} = $self->get_cadd_score( $abs_pos, $base, $var_allele );
    }
  }
  
  my (@gene_data, @snp_data) = ();

  # get gene annotations at site
  if ($gan) {
    for my $gene_dbs ( $self->_all_dbm_gene ) {
      my $kch = $gene_dbs->[$chr_index];

      # if there's no file for the track then it will be undef
      next unless defined $kch;

      # all kc values come as aref's of href's
      my $rec_aref = $kch->db_get($abs_pos);

      if (defined $rec_aref) {
        for my $rec_href ( @$rec_aref ) {
          for my $allele (@var_alleles) {
            $rec_href->{minor_allele} = $allele;
            push @gene_data, Seq::Site::Annotation->new( $rec_href );
          }
        }
      }
    }
  }
  $record{gene_data} = \@gene_data;

  # get snp annotations at site
  if ($snp) {
    for my $snp_dbs ( $self->_all_dbm_snp ) {
      my $kch = $snp_dbs->[$chr_index];

      # if there's no file for the track then it will be undef
      next unless defined $kch;

      # all kc values come as aref's of href's
      my $rec_aref = $kch->db_get($abs_pos);
      if (defined $rec_aref) {
        for my $rec_href ( @$rec_aref) {
          push @snp_data, Seq::Site::Snp->new($rec_href);
        }
      }
    }
  }
  $record{snp_data} = \@snp_data;

  # create object for href export
  my $obj = Seq::Annotate::Snp->new( \%record );
  return $obj->as_href;
}

# annotate_ref_site returns a hash reference of data for the reference 
# annotation of a particular genomic site
sub annotate_ref_site {
  my ( $self, $chr, $chr_index, $rel_pos, $abs_pos, $ref_allele ) = @_;

  my %record;

  my $site_code = $self->get_base($abs_pos);
  my $base      = $self->get_idx_base($site_code);
  my $gan       = ( $self->get_idx_in_gan($site_code) ) ? 1 : 0;
  my $gene      = ( $self->get_idx_in_gene($site_code) ) ? 1 : 0;
  my $exon      = ( $self->get_idx_in_exon($site_code) ) ? 1 : 0;
  my $snp       = ( $self->get_idx_in_snp($site_code) ) ? 1 : 0;

  if ($ref_allele ne 'NA') {
    if ($base ne $ref_allele) {
      my $msg = sprintf("Error: Discordant ref base at site %s:%d (abs_pos: %d); obs: '%s', got: '%s'",
        $chr, $rel_pos, $abs_pos, $base, $ref_allele);
      $self->_logger->error($msg);
      croak $msg;
    }
  }

  $record{chr} = $chr;
  $record{pos} = $rel_pos;
  $record{abs_pos}   = $abs_pos;
  $record{var_type} = 'REF';
  $record{ref_base}  = $base;

  if ($gene) {
    if ($exon) {
      $record{genomic_type} = 'Exonic';
    }
    else {
      $record{genomic_type} = 'Intronic';
    }
  }
  else {
    $record{genomic_type} = 'Intergenic';
  }

  # get scores at site
  for my $gs ( $self->_all_genome_scores ) {
    $record{scores}{ $gs->name } = $gs->get_score($abs_pos);
  }
  
  my (@gene_data, @snp_data) = ();

  # get gene annotations at site
  if ($gan) {
    for my $gene_dbs ( $self->_all_dbm_gene ) {
      my $kch = $gene_dbs->[$chr_index];

      # if there's no file for the track then it will be undef
      next unless defined $kch;

      # all kc values come as aref's of href's
      my $rec_aref = $kch->db_get($abs_pos);
      
      if (defined $rec_aref) {
        for my $rec_href ( @$rec_aref ) {
          push @gene_data, Seq::Site::Annotation->new( $rec_href );
        }
      }
    }
  }
  $record{gene_data} = \@gene_data;

  # get snp annotations at site
  if ($snp) {
    for my $snp_dbs ( $self->_all_dbm_snp ) {
      my $kch = $snp_dbs->[$chr_index];

      # if there's no file for the track then it will be undef
      next unless defined $kch;

      # all kc values come as aref's of href's
      my $rec_aref = $kch->db_get($abs_pos);
      if (defined $rec_aref) {
        for my $rec_href ( @$rec_aref) {
          push @snp_data, Seq::Site::Snp->new($rec_href);
        }
      }
    }
  }
  $record{snp_data} = \@snp_data;

  # create obj for href export
  my $obj = Seq::Annotate::Snp->new( \%record );
  return $obj->as_href;
}

# annotate_del_sites takes an hash reference of sites and chromosome
#   indicies hash reference and returns a list of the consequences for
#   deleting the site
#   - the site hash reference is defined like so:
#     %site{ abs_pos } = [ chr, pos ]
#   - the chromosome index hash reference is needed to determine the proper
#     array to use for determining the annotation
#   - this funciton works by grouping contiguous sites together and submitting
#     those to _annotate_indel_site_list
sub annotate_del_sites {
  state $check = compile( Object, HashRef, HashRef );
  my ( $self, $chr_index_href, $sites_href ) = $check->(@_);
  my ( @annotations, @contiguous_sites );

  my @abs_sites = sort { $a <=> $b } keys %$sites_href;
  push @contiguous_sites, $abs_sites[0];

  for ( my $i = 1; $i < @abs_sites; $i++ ) {
    if ( $abs_sites[ $i - 1 ] + 1 == $abs_sites[$i] ) {
      push @contiguous_sites, $abs_sites[$i];
    }
    else {
      #say "annotate these sites:" . dump( @contiguous_sites );

      # annotate the sites
      #   - get the relative chr and position
      #   - get the chromosome index (needed to lookup te basic annotation)
      #   - annotate the sites
      my ( $chr, $rel_pos ) = @{ $sites_href->{ $contiguous_sites[0] } };
      my $chr_index = $chr_index_href->{$chr};

      my $records_aref =
        $self->_annotate_indel_sites( $chr, $rel_pos, $chr_index,
        $contiguous_sites[0], $contiguous_sites[-1] );

      # save annotation
      push @annotations, $records_aref;
      # assign annotation to the 1st site
      #p @annotations;

      # clear old sites
      @contiguous_sites = ();

      # add site we are presently on, which allowed us to determine if we were
      # in a contiguous region or not - for the next loop
      push @contiguous_sites, $abs_sites[$i];
    }
  }
  return \@annotations;
}

# annotate_ins_sites takes a hash reference of sites and chromosome indicies
#   hash reference and returns a list of consequences for altering the sites
#   over which the insertion occurs.
#   - the site hash reference differes from the one accepted by
#     annoate_del_sites:
#     %site{ abs_pos } = [ chr, pos, insertion_string ]
sub annotate_ins_sites {
  state $check = compile( Object, HashRef, HashRef );
  my ( $self, $chr_index_href, $sites_href ) = $check->(@_);
  my ( @annotations, @contiguous_sites );

  for my $abs_pos ( sort { $a <=> $b } keys %$sites_href ) {
    my ( $chr, $rel_pos, $all_alleles ) = @{ $sites_href->{$abs_pos} };

    for my $allele ( split /\,/, $all_alleles ) {
      if ( defined $chr && defined $rel_pos && defined $allele ) {
        my $chr_index = $chr_index_href->{$chr};
        my $stop      = $abs_pos + length $allele;
        my $records_aref =
          $self->_annotate_indel_sites( $chr, $rel_pos, $chr_index, $abs_pos, $stop );
        push @annotations, $records_aref;
      }
      else {
        my $msg = sprintf( "ERROR: %s could not process data for site '%d'",
          'annotate_ins_sites()', $abs_pos );
        $self->_logger->error($msg);
        croak $msg;
      }
    }
  }
  return \@annotations;
}

sub _annotate_indel_sites {
  state $check = compile( Object, Str, Int, Int, Int, Int );
  my ( $self, $chr, $rel_start, $chr_index, $abs_start, $abs_stop ) = $check->(@_);

  # TODO: need to think of something that will give me Del vs Ins
  #   - probably just pass the string of ins and if it's empty then it's a del

  # going assign the annotation to the relative start (rel_start) position

  my ( %tx_list, @ref_annotations );

  for ( my $site = $abs_start; $site <= $abs_stop; $site++ ) {
    my $record_href = $self->annotate_ref_site( $chr_index, $site, 'NA');

    # save record
    push @ref_annotations, $record_href;

    # lookup transcript information
    for my $gene_data ( @{ $record_href->{gene_data} } ) {
      my $tx_id = $gene_data->{transcript_id};

      # skip transcripts that have already been looked up
      next if exists $tx_list{$tx_id};

      # loop over all transcript data sets we might have
      for my $dbm_tx ( $self->_all_dbm_tx ) {

        # each transcript is stored as an array reference in the KC database
        my $tx_href = shift @{ $dbm_tx->db_get($tx_id) };

        if ( defined $tx_href ) {
          $tx_list{$tx_id} = $tx_href;
        }
      }
    }
  }
  my $href = {
    indel_type      => 'Del',
    chr             => $chr,
    pos             => $rel_start,
    abs_start_pos   => $abs_start,
    abs_stop_pos    => $abs_stop,
    ref_annotations => \@ref_annotations,
    transcripts     => \%tx_list,
  };
  my $indel    = Seq::Annotate::Indel->new($href);
  return $indel;
}

__PACKAGE__->meta->make_immutable;

1;
