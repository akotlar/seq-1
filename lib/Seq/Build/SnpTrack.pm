package Seq::Build::SnpTrack;

use 5.10.0;
use Moose;
use namespace::autoclean;
extends 'Seq::Build::SparseTrack';
with 'Seq::Serialize::Sparse';

=head1 NAME

Seq::Build::SnpTrack - The great new Seq::Build::SnpTrack!

=head1 VERSION

Version 0.01

=cut

our $VERSION = '0.01';

has snp_id => (
  is => 'rw',
  isa => 'Str',
  required => 1,
  clearer => 'clear_snp_id',
  predicate => 'has_snp_id',
);

has maf => (
  is => 'rw',
  isa => 'Str',
  clearer => 'clear_maf',
  predicate => 'has_maf',
);

has alleles => (
  is => 'rw',
  isa => 'ArrayRef',
  clearer => 'clear_alleles',
  predicate => 'has_alleles',
);

=head1 SYNOPSIS

Quick summary of what the module does.

Perhaps a little code snippet.

    use Seq::Build::SnpTrack;

    my $foo = Seq::Build::SnpTrack->new();
    ...

=head1 EXPORT

A list of functions that can be exported.  You can delete this section
if you don't export anything, such as for a purely object-oriented module.

=head1 SUBROUTINES/METHODS

=head2 function1

=cut

sub serialize_sparse_attrs {
  return qw(abs_pos snp_id alleles);
}

=head1 AUTHOR

Thomas Wingo, C<< <thomas.wingo at emory.edu> >>

=head1 BUGS

Please report any bugs or feature requests to C<bug-seq-build-snptrack at rt.cpan.org>, or through
the web interface at L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=Seq-Build-SnpTrack>.  I will be notified, and then you'll
automatically be notified of progress on your bug as I make changes.




=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc Seq::Build::SnpTrack


You can also look for information at:

=over 4

=item * RT: CPAN's request tracker (report bugs here)

L<http://rt.cpan.org/NoAuth/Bugs.html?Dist=Seq-Build-SnpTrack>

=item * AnnoCPAN: Annotated CPAN documentation

L<http://annocpan.org/dist/Seq-Build-SnpTrack>

=item * CPAN Ratings

L<http://cpanratings.perl.org/d/Seq-Build-SnpTrack>

=item * Search CPAN

L<http://search.cpan.org/dist/Seq-Build-SnpTrack/>

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

1; # End of Seq::Build::SnpTrack
