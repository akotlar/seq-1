package Seq::Serialize::CharGenome;

use 5.10.0;
use strict;
use warnings;
use Carp;
use Moose::Role;

requires qw( substr_char_genome );

=head1 NAME

Seq::Serialize::CharGenome - The great new Seq::Serialize::CharGenome!

=head1 VERSION

Version 0.01

=cut

our $VERSION = 'v0.01';


=head1 SYNOPSIS

Moose Role for dealing with Genome Sized Tracks (e.g., conservation scores) and
their associated sequences of chars.

=head1 Methods

=head2 insert_char

=cut

sub insert_char {
  my $self = shift;
  my ($char, $pos) = @_;
  my $seq_len = $self->length;

  confess "insert_char expects insert value and absolute position"
    unless $char and $pos;

  confess "insert_char expects insert value between 0 and 255"
    unless ($char >= 0 and $char <= 255);

  confess "insert_char expects pos value between 1 and $seq_len"
    unless ($pos >= 1 and $pos <= $seq_len);

  # inserted character is a byproduct of a successful substr event
  my $inserted_char = substr( ${ $self->char_seq }, $pos, 1, pack( 'C', $char));

  return $inserted_char;
}

=head2 insert_score

=cut

sub insert_score {
  my $self = shift;
  my ($score, $pos) = @_;
  my $seq_len = $self->length;

  confess "insert_score expects inserted value to be between 0 and 1"
    unless ($score >= 0 and $score <= 1);

  confess "insert_score expects pos value between 1 and $seq_len"
    unless ($pos >= 0 and $pos <= 1);

  my $char_score    = $self->score2char( $score );
  my $inserted_char = $self->insert_char( $char_score, $pos );
  return $inserted_char;
}

=head2 get_char

=cut

sub get_char {
  my $self = shift;
  my ($pos) = @_;
  confess "get_value expects a position number"
    unless $pos >= 1 and $pos < $self->length;

  return unpack ('C', substr( ${$self->char_seq}, ($pos - 1), 1));
}

=head2 get_score

=cut

sub get_score {
  my $self = shift;
  my ($pos) = @_;
  my $char = $self->get_char( $pos );
  return $self->char2score->( $char );
}

=head1 AUTHOR

Thomas Wingo, C<< <thomas.wingo at emory.edu> >>

=head1 BUGS

Please report any bugs or feature requests to C<bug-seq at rt.cpan.org>, or through
the web interface at L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=Seq>.  I will be notified, and then you'll
automatically be notified of progress on your bug as I make changes.




=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc Seq::Serialize::CharGenome


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
no Moose::Role;

1; # End of Seq::Serialize::CharGenome
