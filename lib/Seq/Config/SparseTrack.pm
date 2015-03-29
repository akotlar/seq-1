use 5.10.0;
use strict;
use warnings;

package Seq::Config::SparseTrack;
# ABSTRACT: Configure a sparse traack
# VERSION

use Moose 2;
use Moose::Util::TypeConstraints;

use namespace::autoclean;
use Scalar::Util qw/ reftype /;

enum SparseTrackType => [ 'gene', 'snp' ];

my @snp_table_fields = qw( chrom chromStart chromEnd name
  alleleFreqCount alleles alleleFreqs );
my @gene_table_fields = qw( chrom strand txStart txEnd cdsStart cdsEnd
  exonCount exonStarts exonEnds proteinID
  alignID );

# track information
has name => ( is => 'ro', isa => 'Str',             required => 1, );
has type => ( is => 'ro', isa => 'SparseTrackType', required => 1, );
has sql_statement => ( is => 'rw', isa => 'Str', );
has features => (
  is       => 'ro',
  isa      => 'ArrayRef[Str]',
  required => 1,
  traits   => ['Array'],
  handles  => { all_features => 'elements', },
);

# file information
has local_dir  => ( is => 'ro', isa => 'Str', required => 1, );
has local_file => ( is => 'ro', isa => 'Str', required => 1, );

around 'sql_statement' => sub {
  my $orig = shift;
  my $self = shift;

  my $new_stmt;
  my $snp_table_fields_str = join( ", ", @snp_table_fields );
  my $gene_table_fields_str = join( ", ", @gene_table_fields, @{ $self->features } );
  if ( $self->$orig(@_) =~ m/\_snp\_fields/ ) {
    ( $new_stmt = $self->$orig(@_) ) =~ s/\_snp\_fields/$snp_table_fields_str/;
  }
  else {
    ( $new_stmt = $self->$orig(@_) ) =~ s/\_gene\_fields/$gene_table_fields_str/;
  }

  return $new_stmt;
};

sub snp_fields_aref {
  return \@snp_table_fields;
}

sub gene_fields_aref {
  return \@gene_table_fields;
}

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
