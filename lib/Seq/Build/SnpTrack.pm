use 5.10.0;
use strict;
use warnings;

package Seq::Build::SnpTrack;
# ABSTRACT: Builds a snp track using dbSnp data, derived from UCSC
# VERSION

use Moose;

use Carp qw/ confess /;
use Cpanel::JSON::XS;
use File::Path qw/ make_path /;
use MongoDB;
use namespace::autoclean;

use Seq::Build::GenomeSizedTrackStr;
use Seq::SnpSite;

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

has genome_seq => (
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
#
# has _snp_db => (
#   is      => 'ro',
#   isa     => 'MongoDB::Collection',
#   builder => '_set_snp_db',
#   lazy    => 1,
# );
#
# sub _set_snp_db {
#   my $self = shift;
#   return $self->mongo_connection->_mongo_collection( $self->name );
# }

sub build_snp_db {
  my $self = shift;

  # set mongo collection
  $self->mongo_connection->_mongo_collection( $self->name )->drop;

  # input
  my $local_dir  = File::Spec->canonpath( $self->local_dir );
  my $local_file = File::Spec->catfile( $local_dir, $self->local_file );
  my $in_fh      = $self->get_read_fh($local_file);

  # output
  my $out_dir = File::Spec->canonpath( $self->genome_index_dir );
  make_path($out_dir);
  my $out_file_name =
    join( ".", $self->genome_name, $self->name, $self->type, 'json' );
  my $out_file_path = File::Spec->catfile( $out_dir, $out_file_name );
  my $out_fh = $self->get_write_fh($out_file_path);

  my ( %header, @snp_sites );
  my $prn_counter = 0;
  while (<$in_fh>) {
    chomp $_;
    my @fields = split( /\t/, $_ );
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
        my $chr     = $data{chrom};
        my $snp_id  = $data{name};
        my $abs_pos = $self->get_abs_pos( $chr, $pos );
        my $record  = {
          abs_pos => $abs_pos,
          snp_id  => $snp_id,
        };
        my $snp_site = Seq::SnpSite->new($record);
        my $base = $self->get_base( $abs_pos, 1 );
        $snp_site->set_feature( base => $base );
        #say "chr: $chr, pos: $pos, abs_pos: $abs_pos";

        if ($min_allele_freq) {
          $snp_site->set_feature( maf => $min_allele_freq, alleles => join( ",", @alleles ) );
        }

        # record keeping - TODO: move into Moose Counter method
        push @snp_sites, $abs_pos;

        my $site_href = $snp_site->as_href;
        $self->mongo_connection->_mongo_collection( $self->name )->insert($site_href);
        #$self->_snp_db->insert($site_href);

        if ( $prn_counter == 0 ) {
          print {$out_fh} "[" . encode_json($site_href);
          $prn_counter++;
        }
        else {
          print {$out_fh} "," . encode_json($site_href);
          $prn_counter++;
        }
      }
    }
  }
  print {$out_fh} "]";
  return \@snp_sites;
}

__PACKAGE__->meta->make_immutable;

1;
