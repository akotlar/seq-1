use 5.10.0;
use strict;
use warnings;

package Seq::Config::SparseTrack;

our $VERSION = '0.001';

# ABSTRACT: Configure a sparse traack
# VERSION

=head1 DESCRIPTION

  @class B<Seq::Config::SparseTrack>

  Base class that decorates @class Seq::Build sql statements (@method
  sql_statement) and performs feature formatting.

Used in:

=begin :list
* @class Seq::Assembly
    Seq::Assembly @extends

      =begin :list
      * @class Seq::Annotate
          Seq::Annotate used in @class Seq only

  * @class Seq::Build
  =end :list
=end :list

@extends

=for :list
* @class Seq::Build::SparseTrack
* @class Seq::Build::GeneTrack
* @class Seq::Build::SnpTrack
* @class Seq::Build::TxTrack

=cut

use Moose 2;
use Moose::Util::TypeConstraints;
use MooseX::Types::Path::Tiny qw/ AbsPath AbsPaths /;

use Carp qw/ croak /;
use namespace::autoclean;
use Type::Params qw/ compile /;
use Types::Standard qw/ Object Maybe Str /;

extends 'Seq::Config::Track';

=type SparseTrackType

=for :list

1. gene

2. snp

=cut

enum SparseTrackType => [ 'gene', 'snp' ];

my @snp_track_fields  = qw( chrom chromStart chromEnd name );
my @gene_track_fields = qw( chrom     strand    txStart   txEnd
  cdsStart  cdsEnd    exonCount exonStarts
  exonEnds  name );

# use: $self->get_kch_file( $chr );
# use: $self->get_dat_file( $chr );

# track information
has snp_track_fields => (
  is      => 'ro',
  isa     => 'ArrayRef',
  builder => '_build_snp_track_fields',
);

sub _build_snp_track_fields {
  return \@snp_track_fields;
}

has gene_track_fields => (
  is      => 'ro',
  isa     => 'ArrayRef',
  builder => '_build_gene_track_fields',
);

sub _build_gene_track_fields {
  return \@gene_track_fields;
}

has type => ( is => 'ro', isa => 'SparseTrackType', required => 1, );
has sql_statement => ( is => 'ro', isa => 'Str', );

has _local_files => (
  is      => 'ro',
  isa     => AbsPaths,
  builder => '_build_raw_local_files',
  traits  => ['Array'],
  handles => { all_local_files => 'elements', },
  coerce  => 1,
  lazy    => 1,
);

sub _build_raw_local_files {
  my $self     = shift;
  my @array    = ();
  my $base_dir = $self->genome_raw_dir;
  for my $file ( @{ $self->local_files } ) {
    push @array, $base_dir->child( $self->type )->child($file);
  }
  return \@array;
}

=property @required {ArrayRef<str>} features

  Defined in the configuration file in the heading feature.
  { sparse_tracks => features => [] }

@example

=for :list
* 'mRNA'
* 'spID'
* 'geneSymbol'

=cut

has features => (
  is       => 'ro',
  isa      => 'ArrayRef[Str]',
  required => 1,
  traits   => ['Array'],
  handles  => { all_features => 'elements', },
);

sub _get_file {
  state $check = compile( Object, Str, Str, Maybe [Str] );
  my ( $self, $chr, $ext, $var ) = $check->(@_);

  my $base_dir = $self->genome_index_dir;
  my $file_name;

  # the chr may either be 'genome' (for the entire transcript db) or a chromosome
  # defined by the configuration file for the organism

  if ( $chr eq 'genome' ) {
    if ( $var eq 'tx' ) {
      $file_name = join ".", $self->name, $var, $chr, $ext;
    }
    elsif ( $var eq 'nn') {
      $file_name = join ".", $self->name, $var, $chr, $ext;
    }
    elsif ( $var eq 'test')  {
      $file_name = join ".", $self->name, $var, $chr, $ext;
    }
    else {
      $file_name = join ".", $self->name, $self->type, $chr, $ext;
    }
  }
  elsif ( grep { /\A$chr\z/ } ( $self->all_genome_chrs ) ) {
    if ( $self->type eq 'gene' and $ext ne 'kch' ) {
      $file_name = join ".", $self->name, $self->type, $chr, $var, $ext;
    }
    else {
      $file_name = join ".", $self->name, $self->type, $chr, $ext;
    }
  }
  else {
    my $msg = sprintf( "Error: asked to create file for unknown chromosome %s", $chr );
    say $msg;
    $self->_logger->error($msg);
    exit(1);
  }
  return $base_dir->child($file_name)->absolute->stringify;
}

sub get_dat_file {
  # state $check = compile( Object, Str, Maybe[Str] );
  my ( $self, $chr, $var ) = @_;
  return $self->_get_file( $chr, 'dat', $var );
}

sub get_kch_file {
  # state $check = compile( Object, Str, Maybe[Str] );
  my ( $self, $chr, $var ) = @_;
  return $self->_get_file( $chr, 'kch', $var );
}

=method @public snp_fields_aref

  Returns array reference containing all (attribute_name => attribute_value}

Called in:

=for :list
* @class Seq::Build::SnpTrack
* @class Seq::Build::TxTrack

@requires:

=for :list
* {Str} $self->type (required by class constructor, guaranteed to be available)
* {ArrarRef<Str>} $self->features (required by class constructor, guaranteed to
  be available)

@returns {ArrayRef|void}

=cut

sub snp_fields_aref {
  my $self = shift;
  if ( $self->type eq 'snp' ) {
    my @out_array;
    #resulting array is @snp_track_fields values followed @self->features values
    push @out_array, @snp_track_fields, @{ $self->features };
    return \@out_array;
  }
  else {
    return;
  }
}

=method @public snp_fields_aref

  Returns array reference containing all {attribute_name => attribute_value}

Called in:

=for :list
* @class Seq::Build::GeneTrack
* @class Seq::Build::TxTrack

@requires:

=for :list
* @property {Str} $self->type (required by class constructor, guaranteed to be
  available)
* @property {ArrarRef<Str>} $self->features (required by class constructor,
  guaranteed to be available)

@returns {ArrayRef|void}

=cut

sub gene_fields_aref {
  my $self = shift;
  if ( $self->type eq 'gene' ) {
    my @out_array;
    push @out_array, @gene_track_fields, @{ $self->features };
    return \@out_array;
  }
  else {
    return;
  }
}

=method @public as_href

  Returns hash reference containing data needed to create BUILD and annotate
  stuff... (i.e., no internals and not all public attributes)

Used in:

=for :list
* @class Seq::Build::GeneTrack
* @class Seq::Build::SnpTrack
* @class Seq::Build

Uses Moose built-in meta method.

@returns {HashRef}

=cut

sub as_href {
  my $self = shift;
  my %hash;
  my @attrs = qw/ name features genome_chrs genome_index_dir genome_raw_dir
    local_files remote_dir remote_files type sql_statement/;
  for my $attr (@attrs) {
    if ( defined $self->$attr ) {
      if ( $self->$attr eq 'genome_index_dir' or $self->$attr eq 'genome_raw_dir' ) {
        $hash{$attr} = $self->$attr->stringify;
      }
      elsif ( $self->$attr ) {
        $hash{$attr} = $self->$attr;
      }
    }
  }
  return \%hash;
}

__PACKAGE__->meta->make_immutable;

1;
