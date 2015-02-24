package Seq::Build::GeneTrack;

use 5.10.0;
use Carp qw( croak );
use Moose;
use namespace::autoclean;
extends 'Seq::GeneTrack';

=head1 NAME

Seq::Build::GeneTrack - The great new Seq::Build::GeneTrack!

=head1 VERSION

Version 0.01

=cut

our $VERSION = '0.01';

=head1 SYNOPSIS

This module is used to seralize and store the position of similar information
or types.

What is a type? Good question. A type is either 'snpLike', 'geneLike', or
'exonLike'.

How are types used? Another good question. Let's back up a step and say that
the ultiamte goal is to build an index of the genome that has information
stored about each base - e.g., is the base coding, intergenic, a snp. To do
this, we encode each base as a char and use 4 bits to store the base itself and
are left with the other 4 to store other information. We have choose to store:
  - snpLike tracks  => SNVs, indels from dbSNP or ClinVar
  - exonLike tracks => transcript sort of info information
  - geneLike tracks => intergenic, genic

=head1 METHODS

=head2 save_site_and_seralize

=cut

sub build_gene_db {
  my $self = shift;

  my $gene_site = Seq::GeneSite->new( save => 'disk' );
  my %header;
  my $fh = $self->get_fh;
  while (<$fh>)
  {
    chomp $_;
    my @fields = split(/\t/, $_);
    if ($.==1)
    {
      map { $header{$fields[$_]} = $_ } (0..$#fields);
      next;
    }
    my %data = map { $_ => $fields[ $header{$_} ] } @gene_attribs;

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

    perldoc Seq::Build::GeneTrack


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

1; # End of Seq::Build::GeneTrack
