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
  handles  => [ 'get_abs_pos', 'get_base', 'exists_chr_len', 'genome_length' ],
);

has bdb_connection => (
  is       => 'ro',
  isa      => 'Seq::BDBManager',
  required => 1,
  handles  => [ 'db_put', 'db_get' ],
);

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

sub _get_range_list {
  my ( $self, $site_aref ) = @_;
  my @s_aref = sort {$a <=> $b } @$site_aref;
  my $last_site = 0;
  my @sites;
  for my ($i = 0; $i < @s_aref; $i++) {
    if ($i == 0 ) {
      push @sites, $s_aref[$i];
    }
    elsif ( $last_site + 1 != $s_aref[$i]) {
      push @sites, $last_site;
    }
    $last_site = $s_aref[$i];
  }
  push @sites, $last_site;
  my @ranges;
  for (my $i = 0; $i @sites; $i += 2 ) {
    push @ranges, join("\t", $sites[$i], $sites[$i+1]);
  }
  return \@ranges;
}

__PACKAGE__->meta->make_immutable;

1;
