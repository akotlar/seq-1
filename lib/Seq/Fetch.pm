package Seq::Fetch;

use 5.10.0;
use Moose;
use namespace::autoclean;
use Scalar::Util qw( reftype openhandle );
use DDP;

=head1 NAME

Seq::Fetch - The great new Seq::Fetch!

=head1 VERSION

Version 0.01

=cut

our $VERSION = '0.01';

has genome_name => ( is => 'ro', isa => 'Str', required => 1, );
has genome_description => ( is => 'ro', isa => 'Str', required => 1, );
has genome_chrs => (
  is => 'ro',
  isa => 'ArrayRef[Str]',
  traits => ['Array'],
  required => 1,
);

# for now, `genome_raw_dir` is really not needed since the other tracks
#   specify a directory and file to use for each feature
has genome_raw_dir => ( is => 'ro', isa => 'Str', required => 1 );
has genome_index_dir => ( is => 'ro', isa => 'Str', required => 1 );
has genome_sized_tracks => (
  is => 'ro',
  isa => 'ArrayRef[Seq::Fetch::Files]',
  required => 1,
);
has annotation_tracks => (
  is => 'ro',
  isa => 'ArrayRef[Seq::Fetch::Sql]',
);

sub fetch_annotation_tracks {
  my $self = shift;
  my $annotation_tracks_aref = $self->annotation_tracks;
  for my $track (@$annotation_tracks_aref)
  {
    $track->write_sql_data;
  }
}

sub say_fetch_genome_size_tracks {
  my ($self, $fh)  = @_;
  confess "say_fetch_genome_size_tracks expects an open filehandle"
    unless openhandle($fh);

  my $genome_sized_tracks = $self->genome_sized_tracks;
  for my $track (@$genome_sized_tracks)
  {
    say $fh $track->say_fetch_files_script;
  }
}

sub say_process_genome_size_tracks {
  my ($self, $fh)  = @_;
  confess "say_process_genome_size_tracks expects an open filehandle"
    unless openhandle($fh);

  my $genome_sized_tracks = $self->genome_sized_tracks;
  for my $track (@$genome_sized_tracks)
  {
    say $fh $track->say_process_files_script
      if $track->say_process_files_script;
  }
}


sub BUILDARGS {
  my $class = shift;
  my $href = $_[0];
  if (scalar @_ > 1 || reftype($href) ne "HASH")
  {
    confess "Error: Seq::Fetch Expected hash or hash reference";
  }
  else
  {
    my %new_hash;
    for my $annotation_track ( @{ $href->{annotation_tracks} } )
    {
      $annotation_track->{genome_name} = $href->{genome_name};
      push @{ $new_hash{annotation_tracks} },
        Seq::Fetch::Sql->new( $annotation_track );
    }
    for my $genome_track ( @{ $href->{genome_sized_tracks} } )
    {
      $genome_track->{genome_chrs} = $href->{genome_chrs};
      push @{ $new_hash{genome_sized_tracks} },
        Seq::Fetch::Files->new( $genome_track );
    }
  for my $attrib (qw( genome_name genome_description genome_chrs
      genome_raw_dir genome_index_dir ))
    {
      $new_hash{$attrib} //= $href->{$attrib} || "";
    }
    return $class->SUPER::BUILDARGS(\%new_hash);
  }
}

=head1 SYNOPSIS

Quick summary of what the module does.

Perhaps a little code snippet.

    use Seq::Fetch;

    my $foo = Seq::Fetch->new();
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

Please report any bugs or feature requests to C<bug-seq-fetch at rt.cpan.org>, or through
the web interface at L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=Seq-Fetch>.  I will be notified, and then you'll
automatically be notified of progress on your bug as I make changes.




=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc Seq::Fetch


You can also look for information at:

=over 4

=item * RT: CPAN's request tracker (report bugs here)

L<http://rt.cpan.org/NoAuth/Bugs.html?Dist=Seq-Fetch>

=item * AnnoCPAN: Annotated CPAN documentation

L<http://annocpan.org/dist/Seq-Fetch>

=item * CPAN Ratings

L<http://cpanratings.perl.org/d/Seq-Fetch>

=item * Search CPAN

L<http://search.cpan.org/dist/Seq-Fetch/>

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

1; # End of Seq::Fetch
