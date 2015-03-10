package Seq::Build::GenomeSizedTrackChar;

use 5.10.0;
use Carp qw( confess croak );
use File::Path;
use File::Spec;
use Moose;
use namespace::autoclean;
use Scalar::Util qw( reftype );
use YAML::XS;
extends 'Seq::Config::GenomeSizedTrack';
with 'Seq::Serialize::CharGenome', 'Seq::IO';

=head1 NAME

Seq::Build::GenomeSizedTrackChar - The great new Seq::Build::GenomeSizedTrackChar!

=head1 VERSION

Version 0.01

=cut

our $VERSION = '0.01';

has length => (
  is => 'rw',
  isa => 'Int',
);

has chr_len => (
  is => 'rw',
  isa => 'HashRef[Str]',
  traits => ['Hash'],
  handles => {
    exists_chr_len => 'exists',
    get_chr_len => 'get',
  },
);

# char_seq stores a string of chars
has char_seq => (
  is => 'rw',
  lazy => 1,
  writer => undef,
  builder => '_build_char_seq',
  isa => 'ScalarRef',
  clearer => 'clear_char_seq',
  predicate => 'has_char_seq',
);

# holds a subroutine that converts chars to a score for the track, which is
#   used to decode the score
has char2score => (
  is => 'ro',
  isa => 'CodeRef',
);

# holds a subroutine that converts scores to a char for the track, which is
#   used to encode the scores

has score2char => (
  is => 'ro',
  isa => 'CodeRef',
);

=head1 SYNOPSIS

This module holds a genome-size index that are stored in a single string of
chars. It can return either the code (0..255 at the site) or the scaled value
between 0 and 1. The former is useful for storing encoded information (e.g.,
if a site is translated, is a SNP, etc.) and the later is useful for holding
score-like information (e.g., conservation scores).

=head1 METHODS

=head2 substr_char_genome

=cut

sub _build_char_seq {
  my $self = shift;
  my $char_seq = "";
  for ( my $pos = 0; $pos < $self->length; $pos++ )
  {
    $char_seq .= pack('C', 0);
  }
  return \$char_seq;
}

sub get_abs_pos {
  my $self = shift;
  my ( $chr, $pos ) = @_;
  unless ($self->exists_chr_len( $chr ))
  {
    confess "$chr not known get_abs_pos()\n";
  }
  my $abs_pos = $self->get_chr_len( $chr ) + $pos;
  return $abs_pos;
}

sub write_char_seq {
  # write idx file
  my $self        = shift;
  my $file        = join(".", $self->name, $self->type, 'idx');
  my $index_dir   = File::Spec->cannonpath( $self->genome_index_dir );
  my $target_file = File::Spec->catfile( $index_dir, $file );
  my $fh          = $self->get_write_bin_fh( $target_file );
  print { $fh } ${ $self->char_seq };
  close $fh;

  # write char_len file for genome
  if ($self->type eq "genome")
  {
    $file        = join(".", $self->name, $self->type, 'chr_len');
    $index_dir   = File::Spec->cannonpath( $self->genome_index_dir );
    $target_file = File::Spec->catfile( $index_dir, $file );
    $fh          = $self->get_write_bin_fh( $target_file );
    print { $fh } Dump( $self->chr_len );
  }
}

sub build_idx {
  my ($self, $genome_str, $exon_href, $flank_exon_href, $snp_href) = @_;

  # TODO: check for genome_str ...
  
  confess "build_idx() expected a 3 hashes - exon, flanking exon, and snp sites"
    unless reftype( $exon_href ) eq "HASH"
      and reftype( $flank_exon_href ) eq "HASH"
      and reftype( $snp_href ) eq "HASH";

  for ( my $pos = 0; $pos < $self->length; $pos++ )
  {
    my $this_pos = $pos + 1;
    my $this_base = uc $genome_str->get_str( $pos );
    my ( $in_gan, $in_gene, $in_exon, $in_snp ) = ( 0, 0, 0, 0 );

    $in_gan   = 1 if exists $exon_href->{$this_pos} || exists $flank_exon_href->{$this_pos};
    $in_gene  = $self->get_char( $pos );
    $in_exon  = 1 if exists $exon_href->{$this_pos};
    $in_snp   = 1 if exists $snp_href->{$this_pos};

    my $site_code = $self->get_idx_code( $this_base, $in_gan, $in_gene, $in_exon, $in_snp );
    if ( $site_code )
    {
      $self->insert_char( $pos, $site_code );
    }
    else
    {
      confess "fatal error at base: $pos ($this_base)\n" .
        "in_gan: $in_gan, in_gene: $in_gene, in_exon: $in_exon, in_snp: $in_snp";
    }
  }
}

sub set_gene_regions {
  my ( $self, $tx_starts_href ) = @_;

  # note: - tx = transcript
  #       - the $tx_starts_href is a hash with keys that are
  #         tx start sites and values are arrays of end values

  confess "set_gene_regions() can only be done on a genome type, not " . $self->type . "\n"
    unless $self->type eq "genome";
  confess "set_gene_regions() requires an array reference of transcript coordinates\n"
    unless reftype( $tx_starts_href ) eq "HASH";

  my @sorted_tx_starts = sort { $a <=> $b } keys %$tx_starts_href;

  # variables
  my ($i, $tx_start, $tx_stop) = ( 0, 0, 0 );

  # pick the 1st start site
  $tx_start = $sorted_tx_starts[$i];
  $i++;
  my @tx_stops = sort { $b <=> $a } @{ $tx_starts_href->{$tx_start} };
  $tx_stop  = shift @tx_stops;

  # recall the char string will be initialized to Zero's already so we only
  # need to consider when we are in a gene region
  for (my $pos = 0; $pos < $self->length; $pos++ )
  {
    if ( $pos > ( $tx_start - 1 ) && $pos < ( $tx_stop - 1 ) )
    {
      $self->insert_char( $pos, '1' );
    }
    elsif ( $pos == ( $tx_stop - 1 ) )
    {
      # end of coding portion of genome?
      if ( $i < scalar @sorted_tx_starts)
      {
        $self->insert_char( $pos, '1' );
        # pick a new tx start and stop with a stop beyond the present position
        while ( ( $tx_stop - 1 ) <= $pos )
        {
          $tx_start = $sorted_tx_starts[$i];
          $i++;
          my @tx_stops = sort { $b <=> $a } @{ $tx_starts_href->{$tx_start} };
          $tx_stop  = shift @tx_stops;
        }
      }
    }
  }
}

sub BUILDARGS {
  my $class = shift;
  my $href  = $_[0];
  if (scalar @_ > 1 || reftype($href) ne "HASH")
  {
    confess "Error: Seq::Build::GenomeSizedTrackChar expects hash reference.\n";
  }
  else
  {
    my %hash;
    if ($href->{type} eq "score")
    {
      if ($href->{name} eq "phastCons")
      {
        $hash{score2chr}  = sub { return (int ( $_ * 254 ) + 1) };
        $hash{char2score} = sub { return ( $_ - 1 ) / 254 };
      }
      elsif ($href->{name} eq "phyloP")
      {
        $hash{score2chr}  = sub { return (int ( $_ * ( 127 / 30 ) ) + 128) };
        $hash{char2score} = sub { return ( $_ - 128 ) / ( 127 / 30 ) }
      }
    }

    # add remaining values to hash
    # if char2score or score2char are set
    # then the defaults will be overridden
    for my $attr (keys %$href)
    {
      $hash{$attr} = $href->{$attr};
    }
    return $class->SUPER::BUILDARGS(\%hash);
  }
}
=head1 AUTHOR

Thomas Wingo, C<< <thomas.wingo at emory.edu> >>

=head1 BUGS

Please report any bugs or feature requests to C<bug-seq at rt.cpan.org>, or through
the web interface at L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=Seq>.  I will be notified, and then you'll
automatically be notified of progress on your bug as I make changes.




=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc Seq::Build::GenomeSizedTrackChar


You can also look for information at:

=over 4

=item * RT: CPAN's request tracker (report bugs here)

L<http://rt.cpan.org/NoAuth/Bugs.html?Dist=Seq>

=item * AnnoCPAN: Annotated CPAN documentation

L<http://annocpan.org/dist/Seq>

=item * CPAN Ratings

L<http://cpanratings.perl.org/d/Seq>

=item * Search CPAN

L<http://search.cpan.org/dist/Seq/>

=back


=head1 ACKNOWLEDGEMENTS


=head1 LICENSE AND COPYRIGHT

Copyright 2015 Thomas Wingo.

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program.  If not, see L<http://www.gnu.org/licenses/>.


=cut

__PACKAGE__->meta->make_immutable;

1; # End of Seq::Build::GenomeSizedTrackChar
