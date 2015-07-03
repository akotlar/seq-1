use 5.10.0;
use strict;
use warnings;

=head1 DESCRIPTION

  @class B<Seq::Config::SparseTrack>
 
  Base class that decorates @class Seq::Build sql statements (@method sql_statement), and performs feature formatting

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
package Seq::Config::SparseTrack;
# ABSTRACT: Configure a sparse traack
# VERSION

use Moose 2;
use Moose::Util::TypeConstraints;
use Carp qw/ croak /;

use namespace::autoclean;

enum SparseTrackType => [ 'gene', 'snp' ];

my @snp_track_fields  = qw( chrom chromStart chromEnd name );
my @gene_track_fields = qw( chrom     strand    txStart   txEnd
  cdsStart  cdsEnd    exonCount exonStarts
  exonEnds  name );

# genome assembly info
has genome_name => ( is => 'ro', isa => 'Str', required => 1, );
has genome_chrs => (
  is      => 'ro',
  isa     => 'ArrayRef[Str]',
  traits  => ['Array'],
  handles => { all_genome_chrs => 'elements', },
);

# track information
has name => ( is => 'ro', isa => 'Str',             required => 1, );
has type => ( is => 'ro', isa => 'SparseTrackType', required => 1, );
has sql_statement => ( is => 'ro', isa => 'Str', );

=property @required {ArrayRef<str>} features  

  This attribute is defined in the config yaml file, in the structure { spare_stracks => features => [] }

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

# file information
has genome_index_dir => ( is => 'ro', isa => 'Str', );
has local_dir        => ( is => 'ro', isa => 'Str', required => 1, );
has local_file       => ( is => 'ro', isa => 'Str', required => 1, );

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
    # fields matches the characters fields literally (case sensitive)
    # x modifier: extended. Spaces and text after a # in the pattern are ignored
    # m modifier: multi-line. Causes ^ and $ to match the begin/end of each line (not only begin/end of string)
    if ( $self->$orig(@_) =~ m/\_snp\_fields/xm ) 
    {
      #substitute _snp_fields in statement for the comma separated string of snp_track_fields and SparseTrack features
      ( $new_stmt = $self->$orig(@_) ) =~ s/\_snp\_fields/$snp_table_fields_str/xm;
    }
    elsif ( $self->$orig(@_) =~ m/_asterisk/xm ) 
    {
      ( $new_stmt = $self->$orig(@_) ) =~ s/\_asterisk/\*/xm;
    }
  }
  elsif ( $self->type eq 'gene' ) 
  {
    my $gene_table_fields_str = join( ", ", @gene_track_fields, @{ $self->features } );
    
    if ( $self->$orig(@_) =~ m/\_gene\_fields/xm ) 
    {
      ( $new_stmt = $self->$orig(@_) ) =~ s/\_gene\_fields/$gene_table_fields_str/xm;
    }
  }
  return $new_stmt;
};

=method @public snp_fields_aref

  Returns array reference containing all (attribute_name => attribute_value}

Called in:

=for :list
* @class Seq::Build::SnpTrack
* @class Seq::Build::TxTrack 

@requires:

=for :list
* {Str} $self->type (required by class constructor, guaranteed to be available) 
* {ArrarRef<Str>} $self->features (required by class constructor, guaranteed to be available)

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

  Returns array reference containing all (attribute_name => attribute_value}

Called in: 

=for :list
* @class Seq::Build::GeneTrack
* @class Seq::Build::TxTrack

@requires:

=for :list
* @property {Str} $self->type (required by class constructor, guaranteed to be available) 
* @property {ArrarRef<Str>} $self->features (required by class constructor, guaranteed to be available)

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
 
  Returns hash reference containing all (attribute_name => attribute_value}

Used in:

=for :list
* @class Seq::Build::GeneTrack
* @class Seq::Build::SnpTrack
* @class Seq::Build

@requires @method $self-meta->get_all_attributes 
  Moose function. Returns 1 if $method_name exists as property in @property $self->{attributes}, 
  including all has=>property() declarations in the object on which SparseTrack was called

@returns {HashRef}

=cut
sub as_href {
  my $self = shift;
  my %hash;
  for my $attr ( $self->meta->get_all_attributes ) {
    my $name = $attr->name;
    if ( defined $self->$name ) {
      if ( $self->$name ) {
        $hash{$name} = $self->$name;
      }
    }
  }
  return \%hash;
}

__PACKAGE__->meta->make_immutable;

1;
