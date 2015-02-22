package Seq::Fetch::Files;

use 5.10.0;
use Carp;
use File::Path;
use File::Spec;
use Moose;
use namespace::autoclean;
extends 'Seq::Config::GenomeSizedTrack';

use DDP;

=head1 NAME

Seq::Fetch::Files - The great new Seq::Fetch::Files!

=head1 VERSION

Version 0.01

=cut

our $VERSION = '0.01';

has act => ( is => 'ro', isa => 'Bool', );
has verbose => ( is => 'ro', isa => 'Bool', );

=head1 SYNOPSIS

Quick summary of what the module does.

Perhaps a little code snippet.

    use Seq::Fetch::Files;

    my $foo = Seq::Fetch::Files->new();
    ...

=head1 EXPORT

A list of functions that can be exported.  You can delete this section
if you don't export anything, such as for a purely object-oriented module.

=head1 SUBROUTINES/METHODS

=head2 say_fetch_files_script

=cut

sub say_fetch_files_script {

  my $self = shift;

  my $name = $self->name;
  # get rsync cmd and opts
  my $rsync_opts = $self->_get_rsync_opts;

  # check required parameters are passed
  croak "cannot determine rsync options " unless $rsync_opts;

  # make directory
  my $local_dir         = File::Spec->canonpath( $self->local_dir );
  my $remote_dir        = $self->remote_dir;
  my $remote_files_aref = $self->remote_files;
  my $command           = "rsync $rsync_opts rsync://$remote_dir";
  my @rsync_cmds        = map { "$command/$_ ."; } @$remote_files_aref;

  my $script = join( "\n",
    "mkdir -p $local_dir",
    "cd $local_dir",
    @rsync_cmds,
    "cd -",
    "" );
  return $script;
}

=head2 say_process_files_script

=cut

sub say_process_files_script {
  my $self = shift;

  my $local_dir = File::Spec->canonpath( $self->local_dir );
  my $name      = $self->name;
  my @cmds;
  foreach my $method (qw( proc_init_cmds proc_chrs_cmds proc_clean_cmds ))
  {
    next unless $self->$method;
    push @cmds, "cd $local_dir";
    if ($method eq "proc_chrs_cmds") # these cmds are looped over the files
    {
      my $chrs_aref = $self->genome_chrs;
      foreach my $chr (@$chrs_aref)
      {
        my $this_cmd = join("\n", @{ $self->$method });
        $this_cmd =~ s/\$dir/$name/g;
        $this_cmd =~ s/\$chr/$chr/g;
        push @cmds, $this_cmd;
      }
      push @cmds, "cd -";
    }
    else
    {
      my $this_cmd = join("\n", @{ $self->$method });
      push @cmds, $this_cmd;
      push @cmds, "cd - ";
    }
  }
  my $script = (@cmds) ? join( "\n", @cmds ) : undef;
  return $script;
}

=head2 _get_rsync_opts

=cut

sub _get_rsync_opts {
  my $self = shift;
  my $act = $self->act;
  my $verbose = $self->verbose;
  my $opt = "";
  if ($act)
  {
    if ($verbose)
    {
      $opt = "-avzP";
    }
    else
    {
      $opt = "-az";
    }
  }
  else
  {
    if ($verbose)
    {
      $opt = "-navzP";
    }
    else
    {
      $opt = "-naz";
    }
  }
  return $opt;
}

=head1 AUTHOR

Thomas Wingo, C<< <thomas.wingo at emory.edu> >>

=head1 BUGS

Please report any bugs or feature requests to C<bug-seq-build-fetchfiles at rt.cpan.org>, or through
the web interface at L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=Seq-Build-FetchFiles>.  I will be notified, and then you'll
automatically be notified of progress on your bug as I make changes.




=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc Seq::Fetch::Files


You can also look for information at:

=over 4

=item * RT: CPAN's request tracker (report bugs here)

L<http://rt.cpan.org/NoAuth/Bugs.html?Dist=Seq-Build-FetchFiles>

=item * AnnoCPAN: Annotated CPAN documentation

L<http://annocpan.org/dist/Seq-Build-FetchFiles>

=item * CPAN Ratings

L<http://cpanratings.perl.org/d/Seq-Build-FetchFiles>

=item * Search CPAN

L<http://search.cpan.org/dist/Seq-Build-FetchFiles/>

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

1; # End of Seq::Fetch::Files
