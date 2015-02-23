package Seq::Build::GenomeSizedTrackChar;

use 5.10.0;
use Carp;
use File::Path;
use File::Spec;
use Moose;
use namespace::autoclean;
extends 'Seq::Config::GenomeSizedTrackChar';
with 'Seq::Serialize::StrGenome', 'Seq::IO';

=head1 NAME

Seq::Build::GenomeSizedTrackChar - The great new Seq::Build::GenomeSizedTrackChar!

=head1 VERSION

Version 0.01

=cut

has genome_index_dir => (
  is => 'ro',
  isa => 'Str',
  required => 1,
);

has length => (
  is => 'ro',
  isa => 'Int',
);

# str_seq stores a string in a single scalar
has str_seq => (
  is => 'rw',
  writer => undef,
  builder => '_build_str_seq',
  isa => 'ScalarRef[Str]',
  cleaer => 'clear_char_seq',
  predicate => 'has_char_seq',
);

=head1 SYNOPSIS

This module holds a genome-size index that are stored in a single string of
chars. It can return either the code (0..255 at the site) or the scaled value
between 0 and 1. The former is useful for storing encoded information (e.g.,
if a site is translated, is a SNP, etc.) and the later is useful for holding
score-like information (e.g., conservation scores).

=head1 METHODS

=head2 _build_char_seq

=cut

sub _build_str_seq {
  my $self = shift;
  my $str_seq = "";
  return \$str_seq;
}

sub substr_str_genome {
  $_[0]->str_seq;
}
