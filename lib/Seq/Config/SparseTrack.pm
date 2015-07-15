use 5.10.0;
use strict;
use warnings;
use Carp qw/ croak /;

package Seq::Config::SparseTrack;
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

use namespace::autoclean;
use Type::Params qw/ compile /;
use Types::Standard qw/ Str Object /;

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

=function sql_statement (private,)

Construction-time @property sql_statement modifier

@requires:

=begin :list
* @property {Str} $self->type

    @values:

    =begin :list
    1. 'snp'
    2. 'gene'
    =end :list

* @property {ArrarRef<Str>} $self->features
* @property {Str} $self->sql_statement (returned by $self->$orig(@_) )
* @param {Str} @snp_track_fields (global)
=end :list

@return {Str}

=cut

around 'sql_statement' => sub {
  my $orig     = shift;
  my $self     = shift;
  my $new_stmt = "";

  # handle blank sql statements
  return unless $self->$orig(@_);

  # make substitutions into the sql statements
  if ( $self->type eq 'snp' ) {
    my $snp_table_fields_str = join( ", ", @snp_track_fields, @{ $self->features } );

    # \_ matches the character _ literally
    # snp matches the characters snp literally (case sensitive)
    # \_ matches the character _ literally

    # NOTE: the following just defines the perl regex spec and could be removed.
    # fields matches the characters fields literally (case sensitive)
    # x modifier: extended. Spaces and text after a # in the pattern are ignored
    # m modifier: multi-line. Causes ^ and $ to match the begin/end of each line
    #             (not only begin/end of string)
    if ( $self->$orig(@_) =~ m/\_snp\_fields/xm ) {
      # substitute _snp_fields in statement for the comma separated string of
      # snp_track_fields and SparseTrack features
      ( $new_stmt = $self->$orig(@_) ) =~ s/\_snp\_fields/$snp_table_fields_str/xm;
    }
    elsif ( $self->$orig(@_) =~ m/_asterisk/xm ) {
      ( $new_stmt = $self->$orig(@_) ) =~ s/\_asterisk/\*/xm;
    }
  }
  elsif ( $self->type eq 'gene' ) {
    my $gene_table_fields_str = join( ", ", @gene_track_fields, @{ $self->features } );

    if ( $self->$orig(@_) =~ m/\_gene\_fields/xm ) {
      ( $new_stmt = $self->$orig(@_) ) =~ s/\_gene\_fields/$gene_table_fields_str/xm;
    }
  }
  return $new_stmt;
};

sub get_kch_file {
  state $check = compile( Object, Str );
  my ( $self, $chr ) = $check->(@_);
  return $self->_get_file( $chr, 'kch' );
}

sub get_dat_file {
  state $check = compile( Object, Str );
  my ( $self, $chr ) = $check->(@_);
  return $self->_get_file( $chr, 'dat' );
}

sub _get_file {
  my ( $self, $chr, $ext ) = @_;
  my $base_dir = $self->genome_index_dir;
  my $file_name = sprintf( "%s.%s.%s.%s", $self->name, $self->type, $chr, $ext );
  return $base_dir->child($file_name)->absolute->stringify;
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
    local_files remote_dir remote_files type/;
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
