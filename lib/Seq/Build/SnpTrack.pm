use 5.10.0;
use strict;
use warnings;

package Seq::Build::SnpTrack;
# ABSTRACT: Builds a snp track using dbSnp data, derived from UCSC
# VERSION

use Moose 2;

use Carp qw/ confess /;
use Cpanel::JSON::XS;
use File::Path qw/ make_path /;
use MongoDB;
use namespace::autoclean;

use Seq::Build::GenomeSizedTrackStr;
use Seq::Site::Snp;

extends 'Seq::Config::SparseTrack';
with 'Seq::Role::IO';

has genome_index_dir => (
  is       => 'ro',
  isa      => 'Str',
  required => 1,
);

has genome_name => (
  is       => 'ro',
  isa      => 'Str',
  required => 1,
);

has genome_track_str => (
  is       => 'ro',
  isa      => 'Seq::Build::GenomeSizedTrackStr',
  required => 1,
  handles  => [ 'get_abs_pos', 'get_base', ],
);

has mongo_connection => (
  is       => 'ro',
  isa      => 'Seq::MongoManager',
  required => 1,
);

sub build_snp_db {
  my $self = shift;

  # defensively drop anything if the collection already exists
  $self->mongo_connection->_mongo_collection( $self->name )->drop;

  # input
  my $local_dir  = File::Spec->canonpath( $self->local_dir );
  my $local_file = File::Spec->catfile( $local_dir, $self->local_file );
  my $in_fh      = $self->get_read_fh($local_file);

  my ( %header, @snp_sites );
  while (my $line = $in_fh->getline) {

    # taint check
    chomp $line;
    my $clean_line = $self->clean_line($line);
    next unless $clean_line;
    my @fields = split( /\t/, $clean_line );

    if ( $. == 1 ) {
      map { $header{ $fields[$_] } = $_ } ( 0 .. $#fields );
      next;
    }
    my %data = map { $_ => $fields[ $header{$_} ] } @{ $self->snp_fields_aref };
    my ( $allele_freq_count, @alleles, @allele_freqs, $min_allele_freq );

    if ( $data{alleleFreqCount} ) {
      @alleles      = split( /,/, $data{alleles} );
      @allele_freqs = split( /,/, $data{alleleFreqs} );
      my @s_allele_freqs = sort { $b <=> $a } @allele_freqs;
      $min_allele_freq = sprintf( "%0.6f", 1 - $s_allele_freqs[0] );
    }

    if ( $data{name} =~ m/^rs(\d+)/ ) {
      foreach my $pos ( ( $data{chromStart} + 1 ) .. $data{chromEnd} ) {
        my $chr      = $data{chrom};
        my $snp_id   = $data{name};
        my $abs_pos  = $self->get_abs_pos( $chr, $pos );
        my $base     = $self->get_base( $abs_pos, 1 );
        my $snp_site = Seq::Site::Snp->new(
          {
            abs_pos  => $abs_pos,
            snp_id   => $snp_id,
            ref_base => $base,
          }
        );

        my %feature_hash = map { $_ => $data{$_} } ($self->all_features);

        # this is a total hack - MAF might be nice to have but doesn't fit into the
        # present framework well since it's not a 'feature' we retrieve but rather
        # it's calculated... since you get about the same infor with alleleFreqs
        # I'm not really sure it's even needed.
        $feature_hash{maf} = $min_allele_freq if ($min_allele_freq);

        $snp_site->set_snp_feature( %feature_hash );

        push @snp_sites, $abs_pos;

        my $site_href = $snp_site->as_href;
        $self->mongo_connection->_mongo_collection( $self->name )->insert($site_href);
      }
    }
  }
  return \@snp_sites;
}

__PACKAGE__->meta->make_immutable;

1;
