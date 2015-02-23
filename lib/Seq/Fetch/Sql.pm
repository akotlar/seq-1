package Seq::Fetch::Sql;

use 5.10.0;
use Carp;
use Cwd;
use DBI;
use File::Path qw(make_path);
use File::Spec;
use Moose;
use namespace::autoclean;
use Time::localtime;

extends 'Seq::Config::SparseTrack';
with 'Seq::IO';

=head1 NAME

Seq::Serialize - The great new Seq::Fetch::Sql!

=head1 VERSION

Version 0.01

=cut

our $VERSION = '0.01';
my $now_timestamp = sprintf( "%d-%02d-%02d",
                             eval( localtime->year() + 1900 ),
                             eval( localtime->mon() + 1 ),
                             localtime->mday() );

has genome_name => ( is => 'ro', isa => 'Str', required => 1, );
has dsn =>  ( is => 'ro', isa => 'Str', required => 1, default => "DBI:mysql" );
has host => ( is => 'ro', isa => 'Str', required => 1, default => "genome-mysql.cse.ucsc.edu" );
has user => ( is => 'ro', isa => 'Str', required => 1, default => "genome");
has password  => ( is => 'ro', isa => 'Str', );
has port => ( is => 'ro', isa => 'Int', );
has socket => ( is => 'ro', isa => 'Str', );
has act => (is => 'ro', isa => 'Int' );
has verbose => (is => 'ro', isa => 'Int' );


=head1 SYNOPSIS

Quick summary of what the module does.

Perhaps a little code snippet.

    use Seq::Serialize;``

    my $foo = Seq::Fetch::Sqle->new();
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

  my $self = shift;

  # get data
  my $track_statement = $self->sql_statement;

  # get connection handle
  my $dbh = $self->dbh;

  # prepare and execute mysql command
  my $sth = $dbh->prepare($track_statement) or die $dbh->errstr;
  my $rc  = $sth->execute or die $dbh->errstr;

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
  my $self = shift;

  # set directories
  my $dir = File::Spec->canonpath( $self->local_dir );
  my $cwd = cwd();

  # set file names
  my $file_with_time    = $now_timestamp . "." . $self->local_file;
  my $target_file      = File::Spec->catfile( $dir, $file_with_time );
  my $symlink_original = File::Spec->catfile ( ($cwd, $dir), $file_with_time );
  my $symlink_target   = File::Spec->catfile ( ($cwd, $dir), $self->local_file );

  # make target dir
  make_path($dir);

  my $out_fh = $self->get_write_fh( $target_file );

  # get data
  my $sql_data = $self->get_sql_aref;

  # write data
  map { say $out_fh join("\t", @$_); } @$sql_data;

  # link files and return success
  return symlink $symlink_original, $symlink_target;
}



=head1 AUTHOR

Thomas Wingo, C<< <thomas.wingo at emory.edu> >>

=head1 BUGS

Please report any bugs or feature requests to C<bug-seq at rt.cpan.org>, or through
the web interface at L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=Seq>.  I will be notified, and then you'll
automatically be notified of progress on your bug as I make changes.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc Seq::Fetch::Sql


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

1; # End of Seq::Fetch::Sql
