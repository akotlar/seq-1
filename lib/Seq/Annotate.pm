use 5.10.0;
use strict;
use warnings;

package Seq::Annotate;

our $VERSION = '0.001';

# ABSTRACT: Annotates arbitrary sites of a genome assembly.
# VERSION

=head1 DESCRIPTION Seq::Annotate

  Given a genomic position (and a few other needed pieces) this package
  will provides functions that return annotations for the reference, SNP,
  MULTIALLELIC, INS, and DEL sites.

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
* @class Seq::Site::Gene
* @class Seq::Site::Indel
* @class Seq::Site::SNP
* @class Seq::Site::Snp
* @class Seq::Annotate::Indel;
* @class Seq::Annotate::Site;
* @class Seq::Annotate::Snp;
* @role Seq::Role::IO

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
use Cpanel::JSON::XS;

use Seq::GenomeSizedTrackChar;
use Seq::KCManager;
use Seq::Site::Annotation;
use Seq::Site::Gene;
use Seq::Site::Snp;
use Seq::Sites::Indels;

use Seq::Annotate::All;
use Seq::Annotate::Snp;
use Seq::Statistics;

extends 'Seq::Assembly';
with 'Seq::Role::IO';

=property @private {Seq::GenomeSizedTrackChar<Str>} _genome

  Binary-encoded genome string.

@see @class Seq::GenomeSizedTrackChar
=cut
# has messangerHref => (
#   is => 'ro',
#   required => 1,
# );
# has logger => (
#   is => 'ro',
#   isa => 'Seq::Message',
#   handles => ['tee_logger','publishMessage'],
#   required => 1,
# );

has statisticsCalculator => (
  is => 'ro',
  isa => 'Seq::Statistics',
  handles => {
    recordStat => 'record',
    summarizeStats => 'summarize',
    statsRecord => 'statsRecord',
    storeStats => 'storeStats',
  },
  lazy => 1,
  required => 1,
  builder => '_buildStatistics',
);

sub _buildStatistics
{
  my $self = shift;
  return Seq::Statistics->new(debug => $self->debug);
}

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
    $self->tee_logger('error', join( "\n", @$msg_aref) );
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
  $self->tee_logger('info', $msg);
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
      $self->tee_logger('error', join( "\n", @$msg_aref) );
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
    $self->tee_logger('info',$msg);
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
  say "cadd score key: $key; cadd score index: $i" if $self->debug;
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

has discordant_bases => (
  is => 'rw',
  isa => 'Num',
  traits => ['Counter'],
  handles => {
    count_discordant => 'inc',
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
    abs_pos   => 10653420,
    alt_names => {
      protAcc     => 'NM_017766',
      mRNA        => 'NM_017766',
      geneSymbol  => 'CASZ1',
      spID        => 'Q86V15',
      rfamAcc     => 'NA',
      description => 'Test',
      kgID        => 'uc001arp.3',
      spDisplayID => 'CASZ1_HUMAN',
      refseq      => 'NM_017766',
    },
    codon_position => 1,
    codon_number   => 879,
    minor_allele   => 'T',
    ref_base       => 'G',
    ref_codon_seq  => 'AGG',
    ref_aa_residue => 'R',
    site_type      => 'Coding',
    strand         => '-',
    transcript_id  => 'NM_017766',
  };
  my $ann_obj       = Seq::Site::Annotation->new($ann_href);
  my $ann_attr_href = $ann_obj->header_attr;

  # make Seq::Site:Snp object and add attrs to @features
  my $snp_href = {
    "abs_pos"     => 10653420,
    "ref_base"    => "G",
    "snp_id"      => "rs123",
    "snp_feature" => {
      "alleleNs"        => "NA",
      "refUCSC"         => "T",
      "alleles"         => "NA",
      "observed"        => "G/T",
      "name"            => "rs123",
      "alleleFreqs"     => "NA",
      "strand"          => "+",
      "func"            => "fake",
      "alleleFreqCount" => 0,
    },
  };
  my $snp_obj       = Seq::Site::Snp->new($snp_href);
  my $snp_attr_href = $snp_obj->header_attr;

  my $annotation_snp_href = {
    chr          => 'chr1',
    pos          => 10653420,
    var_allele   => 'T',
    allele_count => 2,
    alleles      => 'G,T',
    abs_pos      => 10653420,
    var_type     => 'SNP',
    ref_base     => 'G',
    het_ids      => '',
    hom_ids      => 'Sample_3',
    genomic_type => 'Exonic',
    scores       => {
      cadd     => 10,
      phyloP   => 3,
      phasCons => 0.9,
    },
    gene_data => [$ann_obj],
    snp_data  => [$snp_obj],
  };
  my $ann_snp_obj       = Seq::Annotate::Snp->new($annotation_snp_href);
  my $ann_snp_attr_href = $ann_snp_obj->header_attr;

  my %obj_attrs = map { $_ => 1 }
    ( keys %$ann_snp_attr_href, keys %$ann_attr_href, keys %$snp_attr_href );

  # some features are always expected
  @features =
    qw/ chr pos var_type alleles allele_count genomic_type site_type annotation_type ref_base
    minor_allele /;
  my %exp_features = map { $_ => 1 } @features;

  for my $feature ( sort keys %obj_attrs ) {
    if ( !exists $exp_features{$feature} ) {
      push @features, $feature;
    }
  }

  # add genome score track names to @features
  for my $gs ( $self->_all_genome_scores ) {
    push @features, $gs->name;
  }
  push @features, 'cadd' if $self->has_cadd_track;

  # determine alt features and add them to @features
  my ( @alt_features, %gene_features, %snp_features );

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
  $self->tee_logger('info', $msg);

  $msg = sprintf( "Loaded %d genome score track(s)", $self->count_genome_scores );
  say $msg if $self->debug;
  $self->tee_logger('info',$msg);

  $msg = sprintf( "Loaded %d cadd scores", $self->count_cadd_scores );
  say $msg if $self->debug;
  $self->tee_logger('info',$msg);

  for my $dbm_aref ( $self->_all_dbm_snp, $self->_all_dbm_gene ) {
    my @chrs = $self->all_genome_chrs;
    for ( my $i = 0; $i < @chrs; $i++ ) {
      my $dbm = ( $dbm_aref->[$i] ) ? $dbm_aref->[$i]->filename : 'NA';
      my $msg = sprintf( "Loaded dbm: %s for chr: %s", $dbm, $chrs[$i] );
      say $msg if $self->debug;
      $self->tee_logger('info', $msg);
    }
  }
  for my $dbm_aref ( $self->_all_dbm_tx ) {
    my $dbm = ($dbm_aref) ? $dbm_aref->filename : 'NA';
    my $msg = sprintf( "Loaded dbm: %s for genome", $dbm );
    say $msg if $self->debug;
    $self->tee_logger('info', $msg);
  }
}

sub _var_alleles {
  my ( $self, $alleles_str, $ref_allele ) = @_;
  my (@snpAlleles, @indelAlleles);

  for my $allele ( split /\,/, $alleles_str ) {
    if ( $allele ne $ref_allele && $allele ne 'N' ) {
      if(length $allele == 1) {
        push @snpAlleles, $allele;
      } else {
        push @indelAlleles, $allele;
      }
    }
  }
  return (\@snpAlleles, \@indelAlleles);
}

# sub _var_alleles_no_indel {
#   my ( $self, $alleles_str, $ref_allele ) = @_;
#   my @var_alleles;

#   for my $allele ( split /\,/, $alleles_str ) {
#     if ( $allele ne $ref_allele
#       && $allele ne 'D'
#       && $allele ne 'E'
#       && $allele ne 'H'
#       && $allele ne 'I'
#       && $allele ne 'N' )
#     {
#       push @var_alleles, $allele;
#     }
#   }
#   return \@var_alleles;
# }

# annotate_snp_site returns a hash reference of the annotation data for a
# given position and variant alleles
sub annotate {
  my (
    $self,         $chr,        $chr_index, $rel_pos,
    $abs_pos,      $ref_allele, $var_type,  $all_allele_str,
    $allele_count, $het_ids,    $hom_ids, $id_genos_href, $return_obj
  ) = @_;

  my $site_code = $self->get_base($abs_pos);
  my $base      = $self->get_idx_base($site_code);
  my $gan       = $self->get_idx_in_gan($site_code);
  my $gene      = $self->get_idx_in_gene($site_code);
  my $exon      = $self->get_idx_in_exon($site_code);
  my $snp       = $self->get_idx_in_snp($site_code);

  if ( $base ne $ref_allele ) {
    $self->count_discordant;
  }

  my ($snpAllelesAref, $indelAllelesAref) =
    $self->_var_alleles($all_allele_str, $base );

  if(!(@$snpAllelesAref || @$indelAllelesAref) ) {
    return;
  }
  my $indelAnnotator;
  if(@$indelAllelesAref) {
    $indelAnnotator = Seq::Sites::Indels->new(alleles => $indelAllelesAref);
  }

  my %record;
  $record{chr}          = $chr;
  $record{pos}          = $rel_pos;
  #what does this do? seems to return NA's in practice
  $record{var_allele}   = join ",", @$snpAllelesAref, @$indelAllelesAref;
  $record{allele_count} = $allele_count;
  $record{alleles}      = $all_allele_str;
  $record{abs_pos}      = $abs_pos;
  $record{var_type}     = $var_type;
  $record{ref_base}     = $base;
  $record{het_ids}      = $het_ids;
  $record{hom_ids}      = $hom_ids;

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

  if (@$snpAllelesAref && $self->has_cadd_track) {
    for my $sAllele (@$snpAllelesAref) {
      $record{scores}{cadd} = $self->get_cadd_score($abs_pos, $base, $sAllele);
    }
  }

  my ( @gene_data, @snp_data ) = ();

  # get gene annotations at site
  if ($gan) {
    for my $gene_dbs ( $self->_all_dbm_gene ) {
      my $kch = $gene_dbs->[$chr_index];

      # if there's no file for the track then it will be undef
      next unless defined $kch;

      # all kc values come as aref's of href's
      my $rec_aref = $kch->db_get($abs_pos);

      if($indelAnnotator) {
        $indelAnnotator->findGeneData($rec_aref, $abs_pos, $kch);
      }

      if ( defined $rec_aref ) {
        for my $rec_href (@$rec_aref) {
          if(@$snpAllelesAref) {
            for my $sAllele (@$snpAllelesAref) {
              $rec_href->{minor_allele} = $sAllele;
              push @gene_data, Seq::Site::Annotation->new($rec_href);  
            }
          }
          # if(@$indelAllelesAref) {
          #   for my $iAllele (@$indelAllelesAref) {
          #     $rec_href->{minor_allele} = $iAllele;
          #     push @gene_data, Seq::Site::Indel->new($rec_href);  
          #   }
          # }
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
      my $firstBase;
      my $rec_aref = $kch->db_get($abs_pos);
      if ( defined $rec_aref ) {
        for my $rec_href (@$rec_aref) {
          push @snp_data, Seq::Site::Snp->new($rec_href);
        }
      }
    }
  }
  $record{snp_data} = \@snp_data;

  $self->recordStat($id_genos_href, [$record{var_type}, $record{genomic_type}], 
    $record{ref_base}, \@gene_data, \@snp_data);
  # create object for href export
  my $obj = Seq::Annotate::All->new( \%record );

  if($self->debug) {
    say "In Annotate.pm::annotate, we had these Variants " . $record{var_allele};
    say "In Annotate.pm::annotate, we made this record:";
    p $obj;
  }

  if ($return_obj) {
    return $obj;
  }
  else {
    return $obj->as_href;
  }
}

__PACKAGE__->meta->make_immutable;

1;
