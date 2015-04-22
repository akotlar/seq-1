use 5.10.0;
use strict;
use warnings;

package Seq::Role::Genome;

# ABSTRACT: A moose role for getting the 0-indexed absolute position in the genome
# VERSION

use Moose::Role;

# requires qw/ genome_length exists_chr_len /;

use Carp;
# use Type::Params qw/ compile /;
# use Types::Standard qw/ :types /;

sub get_abs_pos {
  # state $check = compile( Object, Str, Int );
  my ( $class, $chr, $pos ) = @_;

  # confess "get_abs_pos() requires method exists_chr_len()"
  #   unless $class->meta->find_method_by_name('exists_chr_len');
  #
  # confess "get_abs_pos() requires method genome_length()"
  #   unless $class->meta->find_method_by_name('genome_length');

  confess "can't find chr: $chr in build" unless $class->exists_chr_len($chr);
  confess sprintf( "ERROR: get_abs_pos() chr (%s) and pos (%d) should be within %d",
    $chr, $pos, $class->genome_length )
    unless $pos >= 1 and $pos < $class->genome_length;

  # grab the next chromosome start site, but if there is not next chromosome
  # then we're at the end of the genome so get the length of the genome; these
  # values are 0-indexed
  my $next_chr = $class->get_next_chr($chr);
  my $next_chr_start =
    ($next_chr) ? $class->char_genome_length($next_chr) : $class->genome_length;

  # when we call chr:pos we're using a 1-index genome; but str and char genoems
  # are 0-indexed so we subtract 1.
  my $abs_pos = $class->char_genome_length($chr) + $pos - 1;

  if ( $abs_pos > $next_chr_start ) {

    # getting end of chromosome and converting to 1-index for printing
    my $chr_end = $next_chr_start - $class->char_genome_length($chr) + 1;
    croak "get_abs_pos(): site $pos is beyond end of the chr ($chr)"
      . ", which ends at $chr:$chr_end.\n";
  }

  return $abs_pos;
}

no Moose::Role;

1;
