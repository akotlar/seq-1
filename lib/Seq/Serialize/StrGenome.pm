package Seq::Serialize::StrGenome;

use 5.10.0;
use strict;
use warnings;
use Carp;
use Moose::Role;

requires qw( substr_str_genome );

=head1 NAME

Seq::Serialize::StrGenome - The great new Seq::Serialize::StrGenome!

=head1 VERSION

Version 0.01

=cut

our $VERSION = 'v0.01';


=head1 SYNOPSIS

Moose Role for dealing with building Genomes and the associated sequences of
strings.

=head1 Methods

=head2 insert_char

=cut

sub push_str {
  my $self = shift;
  my ( $str ) = @_;

  return eval { ${ $self->str_seq } .= $str; };
}

=head2 get_char

=cut

sub get_str {
  my $self = shift;
  my ($pos) = @_;
  confess "get_value expects a position number"
    unless $pos >= 0 and $pos < length ${ $self->str_seq };

  return substr( ${$self->str_seq}, $pos, 1);
}

=head2 _say_str

This method is for testing purposes. Could break things if you have a really
long string in memory since it will return a copy of that string.

=cut

sub say_str {
  my $self = shift;
  return ${ $self->str_seq };
}

=head1 AUTHOR

Thomas Wingo, C<< <thomas.wingo at emory.edu> >>

=head1 BUGS

Please report any bugs or feature requests to C<bug-seq at rt.cpan.org>, or through
the web interface at L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=Seq>.  I will be notified, and then you'll
automatically be notified of progress on your bug as I make changes.




=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc Seq::Serialize::StrGenome


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

1; # End of Seq::Serialize::StrGenome
