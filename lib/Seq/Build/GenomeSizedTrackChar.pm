package Seq::Build::GenomeSizedTrackChar;

use 5.10.0;
use Carp;
use File::Path;
use File::Spec;
use Moose;
use namespace::autoclean;
extends 'Seq::Config::GenomeSizedTrackChar';
with 'Seq::Serialize::CharGenome',  'Seq::IO';

=head1 NAME

Seq::Build::GenomeSizedTrackChar - The great new Seq::Build::GenomeSizedTrackChar!

=head1 VERSION

Version 0.01

=cut

our $VERSION = '0.01';

has genome_index_dir => (
  is => 'ro',
  isa => 'Str',
  required => 1,
);

has length => (
  is => 'ro',
  isa => 'Int',
);

# char_seq stores a string of chars
has char_seq => (
  is => 'rw',
  lazy => 1,
  writer => undef,
  builder => '_build_char_seq',
  isa => 'ScalarRef[Str]',
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

=head2 _build_char_seq

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


sub write_char_seq {
  my $self        = shift;
  my $file        = $self->type . ".idx";
  my $index_dir   = File::Spec->cannonpath( $self->genome_index_dir );
  my $target_file = File::Spec->catfile( $index_dir, $file );
  my $fh          = $self->get_write_bin_fh( $target_file );
  print $fh ${ $self->char_seq };
  close $fh;
}

sub substr_char_genome {
  $_[0]->char_seq;
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
