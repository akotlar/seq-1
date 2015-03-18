package Seq::Config::SparseTrack;

use 5.10.0;
use Moose;
use Moose::Util::TypeConstraints;
use namespace::autoclean;
use Scalar::Util qw( reftype );

with 'Seq::Role::SparseTrack';

enum SparseTrackType => [ 'gene', 'snp' ];

=head1 NAME

Config::SparseTrack - The great new Config::SparseTrack!

=head1 VERSION

Version 0.01

=cut

our $VERSION = '0.01';

my @snp_table_fields  = qw( chrom chromStart chromEnd name
                            alleleFreqCount alleles alleleFreqs );
my @gene_table_fields = qw( chrom strand txStart txEnd cdsStart cdsEnd
                            exonCount exonStarts exonEnds proteinID
                            alignID );

# track information
has name => ( is => 'ro', isa => 'Str', required => 1, );
has type => ( is => 'ro', isa => 'SparseTrackType', required => 1, );
has sql_statement => ( is => 'rw', isa => 'Str', );
has entry_names => (
  is => 'ro',
  isa => 'ArrayRef[Str]',
  required => 1,
  traits => ['Array'],
  handles => {
    all_names => 'elements',
  },
);

# file information
has local_dir => ( is => 'ro', isa => 'Str', required => 1, );
has local_file => ( is => 'ro', isa => 'Str', required => 1, );


=head1 SYNOPSIS

Quick summary of what the module does.

Perhaps a little code snippet.

    use Config::SparseTrack;

    my $foo = Config::SparseTrack->new();
    ...

=head1 EXPORT

A list of functions that can be exported.  You can delete this section
if you don't export anything, such as for a purely object-oriented module.

=head1 SUBROUTINES/METHODS

=head2 function1

=cut

around 'sql_statement' => sub {
  my $orig = shift;
  my $self = shift;

  my $new_stmt;
  my $snp_table_fields_str  = join(", ", @snp_table_fields);
  my $gene_table_fields_str =  join(", ", @gene_table_fields,
    @{ $self->entry_names });
  if ($self->$orig(@_) =~ m/\_snp\_fields/)
  {
    ($new_stmt = $self->$orig(@_)) =~ s/\_snp\_fields/$snp_table_fields_str/;
  }
  else
  {
    ($new_stmt = $self->$orig(@_)) =~ s/\_gene\_fields/$gene_table_fields_str/;
  }

  return $new_stmt;
};

sub snp_fields_aref {
  return \@snp_table_fields;
}

sub gene_fields_aref {
  return \@gene_table_fields;
}

=head1 AUTHOR

Thomas Wingo, C<< <thomas.wingo at emory.edu> >>

=head1 BUGS

Please report any bugs or feature requests to C<bug-config-Sparsetrack at rt.cpan.org>, or through
the web interface at L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=Config-SparseTrack>.  I will be notified, and then you'll
automatically be notified of progress on your bug as I make changes.




=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc Config::SparseTrack


You can also look for information at:

=over 4

=item * RT: CPAN's request tracker (report bugs here)

L<http://rt.cpan.org/NoAuth/Bugs.html?Dist=Config-SparseTrack>

=item * AnnoCPAN: Annotated CPAN documentation

L<http://annocpan.org/dist/Config-SparseTrack>

=item * CPAN Ratings

L<http://cpanratings.perl.org/d/Config-SparseTrack>

=item * Search CPAN

L<http://search.cpan.org/dist/Config-SparseTrack/>

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

1; # End of Config::SparseTrack
