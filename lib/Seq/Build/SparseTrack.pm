use 5.10.0;
use strict;
use warnings;

package Seq::Build::SparseTrack;
# ABSTRACT: Base class for sparse track building
# VERSION

=head1 DESCRIPTION

  @class Seq::Build::SparseTrack
  #TODO: Check description
  A Seq::Build package specific class, used to define the disk location of the input

  @example

Used in:
=for :list
*

Extended by:
=for :list
* Seq/Build/GeneTrack.pm
* Seq/Build/TxTrack.pm

=cut

use Moose 2;

use Carp qw/ croak /;
use namespace::autoclean;

use Seq::Build::GenomeSizedTrackStr;

extends 'Seq::Config::SparseTrack';

has genome_track_str => (
  is       => 'ro',
  isa      => 'Seq::Build::GenomeSizedTrackStr',
  required => 1,
  handles  => [
    'get_abs_pos', 'get_base',    'exists_chr_len', 'genome_length',
    'in_gan_val',  'in_exon_val', 'in_gene_val',    'in_snp_val'
  ],
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

has force => (
  is      => 'ro',
  isa     => 'Bool',
  default => 0,
);

has debug => (
  is      => 'ro',
  isa     => 'Bool',
  default => 0,
);

sub _has_site_range_file {
  my ( $self, $file ) = @_;
  if ( -f $file ) {
    if ( -s $file ) {
      my $msg = sprintf( "found non-zero file: %s", $file );
      $self->_logger->info($msg);
      return 1;
    }
  }
  my $msg = sprintf( "did not find old file or it was empty: %s", $file );
  $self->_logger->info($msg);
  return;
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

sub _check_header_keys {
  my ( $self, $header_href, $req_header_aref ) = @_;
  my %missing_attr;
  for my $req_attr (@$req_header_aref) {
    $missing_attr{$req_attr}++ unless exists $header_href->{$req_attr};
  }
  if (%missing_attr) {
    my $err_msg =
      sprintf( "annotation misssing expected header information for %s %s chr %s: ",
      $self->name, $self->type, $self->wanted_chr )
      . join ", ", ( sort keys %missing_attr );
    $self->_logger->error($err_msg);
    croak $err_msg;
  }
  else {
    return;
  }
}

__PACKAGE__->meta->make_immutable;

1;
