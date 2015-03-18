package Seq::Role::Genome;

use 5.10.0;
use Carp;
use Moose::Role;
use YAML::XS qw(Dump);
use Scalar::Util qw( reftype );

our $VERSION = 'v0.01';

=head1 SYNOPSIS

Moose Roles for Genomes.

=head1 Methods

=head2 get_abs_pos

Returns an absolute position for a given chr and position.

=cut

sub get_abs_pos {
  my ($self, $chr, $pos ) = @_;

  confess "get_abs_pos() requires method exists_chr_len()"
    unless $self->meta->has_method('exists_chr_len');

  confess "get_abs_pos() requires method genome_length()"
    unless $self->meta->has_method('genome_length');

  confess "get_abs_pos() expects chr ($chr) and pos ($pos) "
    unless $self->exists_chr_len( $chr )
      and $pos >= 1
      and $pos < $self->genome_length;

  # chromsomes are 1-indexed; but str and char genoems are 0-indexed
  my $abs_pos //= $self->get_chr_len( $chr ) + $pos - 1;

  return $abs_pos;
}

no Moose::Role; 1;
