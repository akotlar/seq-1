use 5.10.0;
use strict;
use warnings;

package Seq;

# ABSTRACT: A class for kickstarting building or annotating things
# VERSION

use Moose 2;

use Carp qw/ croak /;
use namespace::autoclean;
use Path::Tiny;
use Text::CSV_XS;

use Seq::Annotate;

with 'Seq::Role::IO';

has snpfile => (
    is  => 'ro',
    isa => 'Path',
);

has configfile => (
    is  => 'ro',
    isa => 'Path',
);

has db_dir => (
    is  => 'ro',
    isa => 'Path'
);

sub get_annotator {
    my $self           = shift;
    my $abs_configfile = path( $self->snpfile )->absolute;
    my $abs_db_dir     = path( $self->db_dir )->absolute;
    return Seq::Annotate->new_with_config( { configfile => $abs_configfile } );
}

sub annotate_snpfile {
    my $self = shift;

    my $snpfile_fh = $self->get_read_fh( path( $self->snpfile )->absolute );
    my $annotator  = $self->get_annotator;

    my ( %header, %ids );
    while ( my $line = $snpfile_fh->getline ) {
        chomp $line;
        my $clean_line = $self->clean_line($line);
        my @fields = split( /\t/, $clean_line );

        if ( $. == 1 ) {
            %header = map { $fields[$_] => $_ } ( 0 .. 5 );
            %ids    = map { $fields[$_] => $_ } ( 6 .. $#fields );
            next;
        }

        # get basic information about variant
        my $chr           = $fields[ $header{Fragment} ];
        my $pos           = $fields[ $header{Position} ];
        my $ref_allele    = $fields[ $header{Reference} ];
        my $type          = $fields[ $header{Type} ];
        my $alleles       = $fields[ $header{Alleles} ];
        my $allele_counts = $fields[ $header{Allele_Counts} ];

        # get carrier ids for variant
        my @carriers =
          $self->_get_minor_allele_carriers( \@fields, \%ids, $ref_allele );

        # get annotation for site
        my $record = $annotator->annotate_site( $chr, $pos );
    }
}

sub _get_minor_allele_carriers {
    my ( $self, $fields_aref, $ids_href, $ref_allele ) = @_;
    my @carriers;

    for my $id ( keys %$ids_href ) {
        my $id_geno = $fields_aref->[ $ids_href->{$id} ];
        my $id_prob = $fields_aref->[ $ids_href->{$id} + 1 ];

        push @carriers, $id if $id_geno ne $ref_allele && $id_geno ne 'N';
    }
    return \@carriers;
}

sub _mung_record {
    my ( $self, $record_href ) = @_;
}

__PACKAGE__->meta->make_immutable;

1;
