use 5.10.0;
use strict;
use warnings;

package Seq::Role::Genome;

# ABSTRACT: A moose role for getting the 0-indexed absolute position in the genome
# VERSION

use Moose::Role;

use Carp;
use Type::Params qw/ compile /;
use Types::Standard qw/ :types /;

sub get_abs_pos {
  state $check = compile( Object, Str, Int );
  my ( $class, $chr, $pos ) = $check->(@_);

  confess "get_abs_pos() requires method exists_chr_len()"
    unless $class->meta->find_method_by_name('exists_chr_len');

  confess "get_abs_pos() requires method genome_length()"
    unless $class->meta->find_method_by_name('genome_length');

  confess "get_abs_pos() expects chr ($chr) and pos ($pos) "
    unless $class->exists_chr_len($chr)
    and $pos >= 1
    and $pos < $class->genome_length;

  # chromsomes are 1-indexed; but str and char genoems are 0-indexed
  my $abs_pos //= $class->get_chr_len($chr) + $pos - 1;

  return $abs_pos;
}

no Moose::Role;

1;
