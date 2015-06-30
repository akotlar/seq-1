use 5.10.0;
use strict;
use warnings;

package Seq::Build::SnpTrack;
# ABSTRACT: Builds a snp track using dbSnp data, derived from UCSC
# VERSION

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

  # input
  my $local_dir  = File::Spec->canonpath( $self->local_dir );
  my $local_file = File::Spec->catfile( $local_dir, $self->local_file );
  my $in_fh      = $self->get_read_fh($local_file);

  # output
  my $index_dir = File::Spec->canonpath( $self->genome_index_dir );
  make_path($index_dir) unless -f $index_dir;

  # input: snp sites
  my $snp_name = join( ".", $self->name, $wanted_chr, 'snp', 'dat' );
  my $snp_file = File::Spec->catfile( $index_dir, $snp_name );
  # check if we need to make the site range file
  #   skip build if this is present
  #   TODO: need a --force option here
  return if $self->_has_site_range_file($snp_file);

  my ( $dbm_name, $dbm_file, $db );

  $self->_logger->info("adding entries for $wanted_chr");

  # 1st line needs to be value that should be added to encoded genome for these sites
  my $snp_fh = $self->get_write_fh($snp_file);
  say {$snp_fh} $self->in_snp_val;

  my ( %header, @snp_sites, @insert_data );
  while ( my $line = $in_fh->getline ) {
    chomp $line;

    my @fields = split /\t/, $line;

    # if there is no header hash assume we're at the begining of the file
    if ( !%header ) {
      %header = map { $fields[$_] => $_ } ( 0 .. $#fields );

      # check if we have enough data to proceed with the build
      $self->_check_essential_header( \%header, [ qw/ chrom chromStart chromEnd name / ] );

      # create dbm file
      $dbm_name = join ".", $self->name, $wanted_chr, $self->type, 'kch';
      $dbm_file = File::Spec->catfile( $index_dir, $dbm_name );
      $self->_logger->info("dbm_file: $dbm_file");
      $db = Seq::KCManager->new(
        filename => $dbm_file,
        mode     => 'create',
        # chosed as ~ 50% of the largest number of SNPs on a chr (chr 2)
        bnum => 3_000_000,
        msiz => 512_000_000,
      );
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
        say {$snp_fh} join "\n", @{ $self->_get_range_list( \@snp_sites ) };
        @snp_sites = ();
        $self->reset_counter;
      }
    }
    $self->inc_counter;
  }
  if ( $self->counter ) {
    say {$snp_fh} join "\n", @{ $self->_get_range_list( \@snp_sites ) };
    @snp_sites = ();
    $self->reset_counter;
  }

  # add a final blank line to the region file; this is a bit of a hack so the c
  # hasher will not crash if there are no entries (after the initial idx mask)
  say {$snp_fh} '';
  $self->_logger->info("finished building snp site db for chr: $wanted_chr");
}



__PACKAGE__->meta->make_immutable;

1;
