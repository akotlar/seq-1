use 5.10.0;
use strict;
use warnings;

package Seq::Build::SnpTrack;
# ABSTRACT: Builds a snp track using dbSnp data, derived from UCSC
# VERSION

=head1 DESCRIPTION

  @class Seq::Build::SnpTrack

  # TODO: Check description
  A single-function, no public property class, which inserts type: snp
  SparseTrack records into a database.

  The input files may be any tab-delimited files with the following basic
  structure: `chrom, start, stop, name`. All columns should have a header and
  any additional columns should be defined as a `feature` in the configuration
  file. By default, the Seq::Fetch and Seq::Fetch::* packages will download and
  write the data in the proper format from a sql server (e.g., UCSC's public
  mysql server).

  @example  my $snp_db = Seq::Build::SnpTrack->new($record);

Used in:
=for :list
* Seq::Build

Extended by: None

=cut

use Moose 2;

use File::Path qw/ make_path /;
use File::Spec;
use namespace::autoclean;

use Seq::Site::Snp;

extends 'Seq::Build::SparseTrack';
with 'Seq::Role::IO';

sub build_snp_db {
  my ( $self, $wanted_chr ) = @_;

  $self->_logger->info("starting to build snp db for chr: $wanted_chr");

  # input files
  my @input_files = $self->all_local_files;

  # prepare output dir, as needed
  $self->genome_index_dir->mkpath unless ( -d $self->genome_index_dir );

  # get the names of the output files
  my $snp_dat_file = $self->get_dat_file( $wanted_chr, $self->type );
  my $dbm_file     = $self->get_kch_file( $wanted_chr );

  # check if we need to make the site range file
  #   skip build if site range file is present or we're forced to overwrite
  return if $self->_has_site_range_file($snp_dat_file) and !$self->force;

  $self->_logger->info("Building entries for $wanted_chr");

  # variable to hold kch object and
  my ( $db, $snp_dat_fh );

  for my $input_file ( @input_files ) {
    my $in_fh = $self->get_write_fh( $input_file );
    my ( %header, @snp_sites, @insert_data );

    while ( my $line = $in_fh->geltine ) {
      chomp $line;

      my @fields = split /\t/, $line;

      # if there is no header hash assume we're at the begining of the file
      if ( !%header ) {
        %header = map { $fields[$_] => $_ } ( 0 .. $#fields );

        # do we have the essential keys?
        $self->_check_header_keys( \%header, [qw/ chrom chromStart chromEnd name /] );

        # do we have the optinally specified keys?
        $self->_check_header_keys( \%header, [ $self->all_features ] );

        # create dbm file
        $self->_logger->info("dbm_file: $dbm_file");
        $db = Seq::KCManager->new(
          filename => $dbm_file,
          mode     => 'create',
          # chosed as ~ 50% of the largest number of SNPs on a chr (chr 2)
          bnum => 3_000_000,
          msiz => 512_000_000,
        );

        # create site-range file
        #   NOTE: 1st line needs to be value that should be added to encoded
        #         genome for these sites
        $snp_dat_fh = $self->get_write_fh($snp_dat_file);
        say {$snp_dat_fh} $self->in_snp_val;
      }

      # process wanted chr
      next unless $fields[0] eq $wanted_chr;

      my %data = map { $_ => $fields[ $header{$_} ] } @{ $self->snp_fields_aref };
      my ( $allele_freq_count, @alleles, @allele_freqs, $min_allele_freq );

      if ( $data{alleleFreqCount} ) {
        @alleles      = split( /,/, $data{alleles} );
        @allele_freqs = split( /,/, $data{alleleFreqs} );
        my @s_allele_freqs = sort { $b <=> $a } @allele_freqs;
        $min_allele_freq = sprintf( "%0.6f", 1 - $s_allele_freqs[0] );
      }

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

        my %feature_hash = map { $_ => $data{$_} } ( $self->all_features );

        # this is a total hack - MAF might be nice to have but doesn't fit into the
        # present framework well since it's not a 'feature' we retrieve but rather
        # it's calculated... since you get about the same info with alleleFreqs
        # I'm not really sure it's even needed.
        $feature_hash{maf} = $min_allele_freq if ($min_allele_freq);

        $snp_site->set_snp_feature(%feature_hash);

        push @snp_sites, $abs_pos;

        my $site_href = $snp_site->as_href;

        $db->db_put( $abs_pos, $site_href );

        if ( $self->counter > $self->bulk_insert_threshold ) {
          say {$snp_dat_fh} join "\n", @{ $self->_get_range_list( \@snp_sites ) };
          @snp_sites = ();
          $self->reset_counter;
        }
      }
      $self->inc_counter;
    }
    if ( $self->counter ) {
      say {$snp_dat_fh} join "\n", @{ $self->_get_range_list( \@snp_sites ) };
      @snp_sites = ();
      $self->reset_counter;
    }
  }

  # add a final blank line to the region file; this is a bit of a hack so the c
  # hasher will not crash if there are no entries (after the initial idx mask)
  say {$snp_dat_fh} '';
  $self->_logger->info("finished building snp site db for chr: $wanted_chr");
}

__PACKAGE__->meta->make_immutable;

1;
