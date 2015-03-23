package Seq::Role::Genome;

use 5.10.0;
use Carp;
use Moose::Role;
use Type::Params qw/ compile /;
use Types::Standard qw/ :types /;

sub get_abs_pos {
  state $check = compile( Object, Str, Int );
  my ( $self, $chr, $pos ) = $check->(@_);

  confess "get_abs_pos() requires method exists_chr_len()"
    unless $self->meta->find_method_by_name('exists_chr_len');

  confess "get_abs_pos() requires method genome_length()"
    unless $self->meta->find_method_by_name('genome_length');

  confess "get_abs_pos() expects chr ($chr) and pos ($pos) "
    unless $self->exists_chr_len($chr)
    and $pos >= 1
    and $pos < $self->genome_length;

  # chromsomes are 1-indexed; but str and char genoems are 0-indexed
  my $abs_pos //= $self->get_chr_len($chr) + $pos - 1;

  return $abs_pos;
}

no Moose::Role;

1;
