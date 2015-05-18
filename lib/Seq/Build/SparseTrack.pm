use 5.10.0;
use strict;
use warnings;

package Seq::Build::SparseTrack;
# ABSTRACT: Base class for sparse track building
# VERSION

use Moose 2;

use namespace::autoclean;

use Seq::Build::GenomeSizedTrackStr;

extends 'Seq::Config::SparseTrack';

with 'MooX::Role::Logger';

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
  handles  => [
    'get_abs_pos', 'get_base',    'exists_chr_len', 'genome_length',
    'in_gan_val',  'in_exon_val', 'in_gene_val',    'in_snp_val'
  ],
);

has dbm_file => (
  is => 'ro',
  isa => 'Str',
);

# has dbm_connection  => (
#   is       => 'ro',
#   isa      => 'Seq::KCWriter',
#   handles  => [ 'db_put', 'db_get' ],
# );

has counter => (
  traits  => ['Counter'],
  is      => 'ro',
  isa     => 'Num',
  default => 0,
  handles => {
    inc_counter   => 'inc',
    dec_counter   => 'dec',
    reset_counter => 'reset',
  }
);

has bulk_insert_threshold => (
  is      => 'ro',
  isa     => 'Num',
  default => 10_000,
);

sub _has_site_range_file {
  my ( $self, $file ) = @_;
  if ( -s $file ) {
    $self->_logger->info( join " ", 'found', $file, 'skipping build' );
    return 1;
  }
  else {
    $self->_logger->info( join " ", 'did not find', $file, 'proceeding with build' );
    return;
  }
}

sub _get_range_list {
  my ( $self, $sites_aref ) = @_;

  # make sites unique
  my %sites = map { $_ => 1 } @$sites_aref;

  # sort sites
  my @s_sites = sort { $a <=> $b } keys %sites;

  # start and stop sites are initially undef since it's concievable that a
  # region starts at zero for some reason
  my ( $start, $stop );
  my $last_site;
  my @pairs;

  for ( my $i = 0; $i < @s_sites; $i++ ) {
    $start = $s_sites[$i] unless defined $start;
    $stop = $last_site if ( $last_site && $last_site + 1 != $s_sites[$i] );
    if ( defined $stop ) {
      push @pairs, join( "\t", $start, $stop );
      $start = $s_sites[$i];
      $stop  = undef;
    }
    $last_site = $s_sites[$i];
  }
  push @pairs, join( "\t", $start, $last_site );
  return \@pairs;
}

__PACKAGE__->meta->make_immutable;

1;
