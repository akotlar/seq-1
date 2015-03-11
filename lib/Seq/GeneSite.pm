package Seq::GeneSite;

use 5.10.0;
use Moose;
use namespace::autoclean;
use Moose::Util::TypeConstraints;
with 'Seq::Serialize::SparseTrack';

=head1 NAME

Seq::GeneSite - The great new Seq::GeneSite!

=head1 VERSION

Version 0.01

=cut

our $VERSION = '0.01';

my %Eu_codon_2_aa = (
    "AAA" => "K", "AAC" => "N", "AAG" => "K", "AAT" => "N",
    "ACA" => "T", "ACC" => "T", "ACG" => "T", "ACT" => "T",
    "AGA" => "R", "AGC" => "S", "AGG" => "R", "AGT" => "S",
    "ATA" => "I", "ATC" => "I", "ATG" => "M", "ATT" => "I",
    "CAA" => "Q", "CAC" => "H", "CAG" => "Q", "CAT" => "H",
    "CCA" => "P", "CCC" => "P", "CCG" => "P", "CCT" => "P",
    "CGA" => "R", "CGC" => "R", "CGG" => "R", "CGT" => "R",
    "CTA" => "L", "CTC" => "L", "CTG" => "L", "CTT" => "L",
    "GAA" => "E", "GAC" => "D", "GAG" => "E", "GAT" => "D",
    "GCA" => "A", "GCC" => "A", "GCG" => "A", "GCT" => "A",
    "GGA" => "G", "GGC" => "G", "GGG" => "G", "GGT" => "G",
    "GTA" => "V", "GTC" => "V", "GTG" => "V", "GTT" => "V",
    "TAA" => "*", "TAC" => "Y", "TAG" => "*", "TAT" => "Y",
    "TCA" => "S", "TCC" => "S", "TCG" => "S", "TCT" => "S",
    "TGA" => "*", "TGC" => "C", "TGG" => "W", "TGT" => "C",
    "TTA" => "L", "TTC" => "F", "TTG" => "L", "TTT" => "F"
);

enum GeneAnnotationType => [ '5UTR', 'Coding', '3UTR', 'non-coding RNA',
                             'Splice Donor', 'Splice Acceptor' ];
enum StrandType         => [ '+', '-' ];

has abs_pos => (
  is => 'rw',
  isa => 'Int',
  required => 1,
  clearer => 'clear_abs_pos',
  predicate => 'has_abs_pos',
);

has base => (
  is => 'rw',
  isa => 'Str',
  required => 1,
  clearer => 'clear_base',
  predicate => 'has_base',
);

has name => (
  is => 'rw',
  isa => 'Str',
  required => 1,
  clearer => 'clear_name',
  predicate => 'has_name',
);

has annotation_type => (
  is => 'rw',
  isa => 'GeneAnnotationType',
  required => 1,
  clearer => 'clear_annotation_type',
  predicate => 'has_annotation_type',
);

has strand => (
  is => 'rw',
  isa => 'StrandType',
  required => 1,
  clearer => 'clear_strand',
  predicate => 'has_strand',
);

# codon at site
has codon_seq => (
  is => 'rw',
  isa => 'Maybe[Str]',
  default => sub { undef },
  clearer => 'clear_codon',
  predicate => 'has_codon',
);

# bp position within the codon
has codon_number => (
  is => 'rw',
  isa => 'Maybe[Int]',
  default => sub { undef },
  clearer => 'clear_codon_site_pos',
  predicate => 'has_codon_site_pos',
);

# amino acide residue # from start of transcript
has codon_position => (
  is => 'rw',
  isa => 'Maybe[Int]',
  default => sub { undef },
  clearer => 'clear_aa_residue_pos',
  predicate => 'has_aa_residue_pos',
);

has aa_residue => (
  is => 'ro',
  lazy => 1,
  builder => '_set_aa_residue',
);

has error_code => (
  is => 'rw',
  isa => 'ArrayRef',
  required => 1,
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

sub _set_aa_residue {
  my $self = shift;
  if ($self->codon_seq)
  {
    return $Eu_codon_2_aa{ $self->codon_seq };
  }
  else
  {
    return undef;
  }
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
