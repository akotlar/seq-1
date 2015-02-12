package Seq::Config;

use 5.10.0;
use Exporter;
use Moose;
use namespace::autoclean;
use Scalar::Util qw(reftype);
use strict;
use warnings;

=head1 NAME

Seq::Config - The great new Seq::Config!

=head1 VERSION

Version 0.01

=cut

our $VERSION = '0.01';

=head1 SYNOPSIS

Set, get, and check configuration.

Perhaps a little code snippet.

    use Seq::Config;

    my $foo = Seq::Config->new();
    ...

=cut

has chr_names => (
  is => 'ro',
  isa => 'ArrayRef[Str]',
  traits => ['Array'],
  required => 1,
);
has gene_track_annotation_names => (
  is => 'ro',
  isa => 'ArrayRef[Str]',
  traits => ['Array'],
  required => 1,
);
has gene_track_name => ( is => 'ro', isa => 'Str', required => 1, );
has gene_track_statement => (is => 'ro', isa => 'Str', required => 1,);
has genome_name => (is => 'ro', isa => 'Str', required => 1,);
has genome_description => (is => 'ro', isa => 'Str', required => 1,);
has phastCons_proc_clean_dir => (
  is => 'ro',
  isa => 'ArrayRef[Str]',
  traits => ['Array'],
);
has phastCons_dir => (is => 'ro', isa => 'Str', required => 1,);
has phastCons_files => (
  is => 'ro',
  isa => 'ArrayRef[Str]',
  traits => ['Array'],
);
has phastCons_proc_chr => (
  is => 'ro',
  isa => 'ArrayRef[Str]',
  traits => ['Array'],
);
has phastCons_proc_init => (
  is => 'ro',
  isa => 'ArrayRef[Str]',
  traits => ['Array'],
);
has phyloP_proc_clean_dir => (
  is => 'ro',
  isa => 'ArrayRef[Str]',
  traits => ['Array'],
);
has phyloP_dir => (is => 'ro', isa => 'Str', required => 1,);
has phyloP_files => (
  is => 'ro',
  isa => 'ArrayRef[Str]',
  traits => ['Array'],
);
has phyloP_proc_chr => (
  is => 'ro',
  isa => 'ArrayRef[Str]',
  traits => ['Array'],
);
has phyloP_proc_init => (
  is => 'ro',
  isa => 'ArrayRef[Str]',
  traits => ['Array'],
);
has seq_dir => (is => 'ro', isa => 'Str', required => 1,);
has seq_files => (
  is => 'ro',
  isa => 'ArrayRef[Str]',
  traits => ['Array'],
  required => 1,
);
has seq_proc_chr => (
  is => 'ro',
  isa => 'ArrayRef[Str]',
  traits => ['Array'],
);
has snp_track_name => (is => 'ro', isa => 'Str', required => 1,);
has snp_track_statement => (is => 'rw', isa => 'Str', required => 1,);

sub BUILDARGS {
  my $class = shift;
  my $href = $_[0];
  if (scalar @_ > 1 || reftype($href) ne "HASH")
  {
    confess "Error creating new Seq::Config, expected hash";
  }
  else
  {
    my %new_hash;
    # set undefined attributes to "" for Str requiring attributes
    for my $attr_name (qw( gene_track_name gene_track_statement genome_name
      genome_description phastCons_dir phyloP_dir seq_dir snp_track_name
      snp_track_statement))
    {
      $new_hash{$attr_name} //= $href->{$attr_name} || "";
    }

    # set undefined attributes as [] for ArrayRef requiring attributes
    for my $attr_name (qw( chr_names gene_track_annotation_names
      phastCons_proc_clean_dir phastCons_files phastCons_proc_chr
      phastCons_proc_init phyloP_proc_clean_dir phyloP_files
      phyloP_proc_chr phyloP_proc_init seq_files seq_proc_chr ))
    {
      $new_hash{$attr_name} //= $href->{$attr_name} || [];
    }
    return $class->SUPER::BUILDARGS(\%new_hash);
  }
}

around 'snp_track_statement' => sub {
  my $orig = shift;
  my $self = shift;
  my @snp_table_fields     = qw( chrom chromStart chromEnd name
                                 alleleFreqCount alleles alleleFreqs
                               );
  my $snp_table_fields_str = join(", ", @snp_table_fields);
  (my $statement = $self->$orig(@_)) =~ s/\$fields/$snp_table_fields_str/;
  return $statement;
};

=head1 AUTHOR

Thomas Wingo, C<< <thomas.wingo at emory.edu> >>

=head1 BUGS

Please report any bugs or feature requests to C<bug-seq at rt.cpan.org>, or through
the web interface at L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=Seq>.  I will be notified, and then you'll
automatically be notified of progress on your bug as I make changes.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc Seq::Config


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

 1; # End of Seq::Config
