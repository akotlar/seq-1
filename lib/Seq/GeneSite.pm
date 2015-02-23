package Seq::GeneSite;

use 5.10.0;
use Moose;
use namespace::autoclean;

=head1 NAME

Seq::GeneSite - The great new Seq::GeneSite!

=head1 VERSION

Version 0.01

=cut

our $VERSION = '0.01';

enum GeneAnnotationTyoe => [ '5UTR', 'Coding', '3UTR', 'non-coding RNA',
                             'Splice Donor', 'Splice Acceptor' ];
enum StrandType         => [ '+', '-' ];

has abs_pos => (
  is => 'rw',
  isa => 'Int',
  required => 1,
  clearer => 'clear_abs_pos',
  predicate => 'has_abs_pos',
)

has name => (
  is => 'rw',
  isa => 'HashRef',
  clearer => 'clear_name',
  predicate => 'has_name',
);

has annotation_type => (
  is => 'rw',
  isa => 'GeneAnnotationType',
  clearer => 'clear_annotation_type',
  predicate => 'has_annotation_type',
);

has strand => (
  is => 'rw',
  isa => 'StrandType',
  clearer => 'clear_strand',
  predicate => 'has_strand',
);

# codon at site
has codon => (
  is => 'rw',
  isa => 'Str',
  clearer => 'clear_codon',
  predicate => 'has_codon',
);

# bp position within the codon
has codon_site_pos => (
  is => 'rw',
  isa => 'Int',
  clearer => 'clear_codon_site_pos',
  predicate => 'has_codon_site_pos',
);

# amino acide residue # from start of transcript
has aa_residue_pos => (
  is => 'rw',
  isa => 'Int',
  clearer => 'clear_aa_residue_pos',
  predicate => 'has_aa_residue_pos',
);

has error_code => (
  is => 'rw',
  isa => 'Int',
  clearer => 'clear_error_code',
  predicate => 'has_error_code',
);

=head1 SYNOPSIS

Quick summary of what the module does.

Perhaps a little code snippet.

    use Seq::GeneSite;

    my $foo = Seq::GeneSite->new();
    ...

=head1 EXPORT

A list of functions that can be exported.  You can delete this section
if you don't export anything, such as for a purely object-oriented module.

=head1 SUBROUTINES/METHODS

=head2 function1

=cut

sub function1 {
}

=head2 function2

=cut

sub function2 {
}

=head1 AUTHOR

Thomas Wingo, C<< <thomas.wingo at emory.edu> >>

=head1 BUGS

Please report any bugs or feature requests to C<bug-seq-GeneSite at rt.cpan.org>, or through
the web interface at L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=Seq-GeneSite>.  I will be notified, and then you'll
automatically be notified of progress on your bug as I make changes.




=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc Seq::GeneSite


You can also look for information at:

=over 4

=item * RT: CPAN's request tracker (report bugs here)

L<http://rt.cpan.org/NoAuth/Bugs.html?Dist=Seq-GeneSite>

=item * AnnoCPAN: Annotated CPAN documentation

L<http://annocpan.org/dist/Seq-GeneSite>

=item * CPAN Ratings

L<http://cpanratings.perl.org/d/Seq-GeneSite>

=item * Search CPAN

L<http://search.cpan.org/dist/Seq-GeneSite/>

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

1; # End of Seq::GeneSite
