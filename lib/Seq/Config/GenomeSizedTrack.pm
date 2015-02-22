package Seq::Config::GenomeSizedTrack;

use 5.10.0;
use Moose;
use Moose::Util::TypeConstraints;
use namespace::autoclean;
use Scalar::Util qw( reftype );

enum GenomeSizedTrackType => [ 'genome', 'score', ];

=head1 NAME

Config::GenomeSizedTrack - The great new Config::GenomeSizedTrack!

=head1 VERSION

Version 0.01

=cut

our $VERSION = '0.01';

has genome_chrs => (
  is => 'ro',
  isa => 'ArrayRef[Str]',
  traits => ['Array'],
  required => 1,
);
has name => ( is => 'ro', isa => 'Str', required => 1, );
has type => ( is => 'ro', isa => 'GenomeSizedTrackType', required => 1, );
has local_dir => ( is => 'ro', isa => 'Str', required => 1, );
has local_files => (
  is => 'ro',
  isa => 'ArrayRef[Str]',
  traits => ['Array'],
  required => 1,
);
has remote_dir => ( is => 'ro', isa => 'Str', required => 1, );
has remote_files => (
  is => 'ro',
  isa => 'ArrayRef[Str]',
  traits => ['Array'],
  required => 1,
);
has proc_init_cmds => (
  is => 'ro',
  isa => 'ArrayRef[Str]',
  traits => ['Array'],
);
has proc_chrs_cmds => (
  is => 'ro',
  isa => 'ArrayRef[Str]',
  traits => ['Array'],
);
has proc_clean_cmds => (
  is => 'ro',
  isa => 'ArrayRef[Str]',
  traits => ['Array'],
);

=head1 SYNOPSIS

Quick summary of what the module does.

Perhaps a little code snippet.

    use Config::GenomeSizedTrack;

    my $foo = Config::GenomeSizedTrack->new();
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

Please report any bugs or feature requests to C<bug-config-annotationtrack at rt.cpan.org>, or through
the web interface at L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=Config-AnnotationTrack>.  I will be notified, and then you'll
automatically be notified of progress on your bug as I make changes.




=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc Config::GenomeSizedTrack


You can also look for information at:

=over 4

=item * RT: CPAN's request tracker (report bugs here)

L<http://rt.cpan.org/NoAuth/Bugs.html?Dist=Config-AnnotationTrack>

=item * AnnoCPAN: Annotated CPAN documentation

L<http://annocpan.org/dist/Config-AnnotationTrack>

=item * CPAN Ratings

L<http://cpanratings.perl.org/d/Config-AnnotationTrack>

=item * Search CPAN

L<http://search.cpan.org/dist/Config-AnnotationTrack/>

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

1; # End of Config::GenomeSizedTrack
