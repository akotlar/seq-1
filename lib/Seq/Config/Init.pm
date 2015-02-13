package Seq::Config::Init;

use 5.10.0;
use DBI;
use Carp;
use Cwd;
use Moose;
use namespace::autoclean;
use Scalar::Util qw(openhandle);
use strict;
use warnings;
use YAML::XS qw(Dump);

=head1 NAME

Seq::Serialize - The great new Seq::Config::Init!

=head1 VERSION

Version 0.01

=cut

our $VERSION = '0.01';

has dsn =>  ( is => 'ro', isa => 'Str', required => 1, default => "DBI:mysql" );
has host => ( is => 'ro', isa => 'Str', required => 1, default => "genome-mysql.cse.ucsc.edu" );
has user => ( is => 'ro', isa => 'Str', required => 1, default => "genome");
has config => (is => 'ro', isa => 'Seq::Config',
  handles => [ 'chr_names', 'seq_dir', 'seq_files', 'seq_proc_chr',
               'phastCons_dir', 'phastCons_files', 'phastCons_proc_init',
               'phastCons_proc_chr', 'phastCons_proc_clean_dir',
               'phyloP_dir', 'phyloP_files', 'phyloP_proc_init',
               'phyloP_proc_chr', 'phyloP_proc_clean_dir',
               'genome_name', 'genome_description', 'gene_track_name',
               'gene_track_statement', 'snp_track_name',  'snp_track_statement',
             ],);
has password  => ( is => 'ro', isa => 'Str', );
has port => ( is => 'ro', isa => 'Int', );
has socket => ( is => 'ro', isa => 'Str', );
has act => (is => 'ro', isa => 'Int' );
has verbose => (is => 'ro', isa => 'Int' );

=head1 SYNOPSIS

Quick summary of what the module does.

Perhaps a little code snippet.

    use Seq::Serialize;``

    my $foo = Seq::Config::Inite->new();
    ...

=head2 dbh

=cut

sub dbh {
  my $self = shift;
  my $dsn = $self->dsn;
  $dsn .= ":" . $self->genome_name;
  $dsn .= ";host=" . $self->host if $self->host;
  $dsn .= ";port=" . $self->port if $self->port;
  $dsn .= ";mysql_socket=" . $self->port_num if $self->socket;
  $dsn .= ";mysql_read_default_group=client";
  my %conn_attrs = (RaiseError => 1, PrintError => 0, AutoCommit => 0);
  return DBI->connect($dsn, $self->user, $self->password, \%conn_attrs);
}

=head2 get_sql_aref

=cut

sub get_sql_aref {

  my ( $self, $type ) = @_;

  # method check
  my $statement_meth = "$type\_track_statement";
  confess "unknown method: $statement_meth" unless $self->meta->get_method($statement_meth);

  # get data
  my $track_statement = $self->$statement_meth;

  # get connection handle
  my $dbh = $self->dbh;

  # prepare and execute mysql command
  my $sth = $dbh->prepare($track_statement) or die $dbh->errstr;
  my $rc  = $sth->execute() or die $dbh->errstr;

  # retrieve data
  my @sql_data;
  while (my @row = $sth->fetchrow_array)
  {
    my @clean_row = map { if (!defined($_))
                          {
                            "NA";
                          }
                          elsif ($_ eq "")
                          {
                            "NA";
                          }
                          else
                          {
                            $_;
                          }
                        } @row;
    push @sql_data, \@row;
  }
  $dbh->disconnect;
  return \@sql_data;
}

=head2 write_sql_data

=cut

sub write_sql_data {
  my ( $self, $type, $fh ) = @_;

  # check required parameters are passed
  confess "write_sql_data expects a type and fh" unless $self
    and $type
    and $fh
    and openhandle($fh);

  # get data
  my $sql_data   = $self->get_sql_aref($type);

  map { say $fh join("\t", @$_); } @$sql_data;
}

=head2 say_fetch_files_script

=cut

sub say_fetch_files_script {

  my( $self, $type ) = @_;

  # get rsync cmd and opts
  my $rsync_opts = $self->_get_rsync_opts;

  # check required parameters are passed
  confess "write_sql_data expects a type of data (e.g., seq)" unless $self
    and $type
    and $rsync_opts;

  # method check
  my $file_dir = "$type\_dir";
  my $file_list = "$type\_files";
  confess "unknown method; $file_dir" unless $self->meta->get_method($file_dir);
  confess "unknown method: $file_list" unless $self->meta->get_method($file_list);
  my $remote_dir = $self->$file_dir;
  my $file_aref = $self->$file_list;
  my $command = "rsync $rsync_opts rsync://$remote_dir";
  my $script = join("\n", "#!/bin/bash", map { "$command/$_ ."; } @$file_aref);
  return $script;
}

=head2 say_process_files_script

=cut

sub say_process_files_script {
  my ( $self, $type ) = @_;

  # check required parameters are passed
  confess "expected type to be seq, phyloP, or phastCons" unless $type eq "seq"
    or $type eq "phyloP"
    or $type eq "phastCons";

  my @cmds;
  foreach my $step (qw( proc_init proc_chr proc_dir_clean ))
  {
    my $method = "$type\_$step";
    next unless $self->meta->get_method($method);
    if ($step eq "proc_chr") # these cmds are looped over the files
    {
      my $chrs_aref = $self->chr_names;
      foreach my $chr (@$chrs_aref)
      {
        my $this_cmd = join("\n", @{ $self->$method });
        $this_cmd =~ s/\$dir/$type/g;
        $this_cmd =~ s/\$chr/$chr/g;
        push @cmds, $this_cmd;
      }
    }
    else
    {
      my $this_cmd = join("\n", @{ $self->$method });
      push @cmds, $this_cmd;
    }
  }
  my $script = (@cmds) ? join("\n", "#!/bin/bash", @cmds) : undef;
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

Please report any bugs or feature requests to C<bug-seq at rt.cpan.org>, or through
the web interface at L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=Seq>.  I will be notified, and then you'll
automatically be notified of progress on your bug as I make changes.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc Seq::Config::Init


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

1; # End of Seq::Config::Init
