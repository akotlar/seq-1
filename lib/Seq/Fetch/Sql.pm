package Seq::Fetch::Sql;
# ABSTRACT: This class fetches and cleans genomic data from sql servers.
=head1 DESCRIPTION

  @class Seq::Fetch::Sql
  # TODO: Check description

  @example

Used in:
=for :list
* Seq::Fetch

Extended by: None

=cut
use 5.10.0;
use Carp;
use Cwd;
use DBI;
use File::Path qw/ make_path /;
use File::Spec;
use Moose;
use namespace::autoclean;
use Time::localtime;

extends 'Seq::Config::SparseTrack';
with 'Seq::Role::IO', 'MooX::Role::Logger';

# time stamp
my $year          = localtime->year() + 1900;
my $mos           = localtime->mon() + 1;
my $day           = localtime->mday;
my $now_timestamp = sprintf( "%d-%02d-%02d", $year, $mos, $day );

has genome_name => ( is => 'ro', isa => 'Str', required => 1, );
has act         => ( is => 'ro', isa => 'Bool', );
has verbose     => ( is => 'ro', isa => 'Bool', );
has dsn => ( is => 'ro', isa => 'Str', required => 1, default => "DBI:mysql" );
has host => (
  is       => 'ro',
  isa      => 'Str',
  required => 1,
  default  => "genome-mysql.cse.ucsc.edu"
);
has user => ( is => 'ro', isa => 'Str', required => 1, default => "genome" );
has password => ( is => 'ro', isa => 'Str', );
has port     => ( is => 'ro', isa => 'Int', );
has socket   => ( is => 'ro', isa => 'Str', );

=method @public sub dbh

  Build database object, and return a handle object

Called in: none

@params:

@return {DBI}
  A connection object

#TODO: either finish the annotation or remove the package.
=cut
sub dbh {
  my $self = shift;
  my $dsn  = $self->dsn;
  $dsn .= ":" . $self->genome_name;
  $dsn .= ";host=" . $self->host if $self->host;
  $dsn .= ";port=" . $self->port if $self->port;
  $dsn .= ";mysql_socket=" . $self->port_num if $self->socket;
  $dsn .= ";mysql_read_default_group=client";
  my %conn_attrs = ( RaiseError => 1, PrintError => 0, AutoCommit => 0 );
  return DBI->connect( $dsn, $self->user, $self->password, \%conn_attrs );
}

sub _write_sql_data {

  my ( $self, $file ) = @_;

  # for return data
  my @sql_data = ();

  if ( $self->act ) {

    # prepare file handle
    my $out_fh = $self->get_write_fh($file);

    # prepare and execute mysql command
    my $dbh = $self->dbh;
    my $sth = $dbh->prepare( $self->sql_statement ) or die $dbh->errstr;
    my $rc  = $sth->execute or die $dbh->errstr;

    # retrieve data
    my $line_cnt = 0;
    while ( my @row = $sth->fetchrow_array ) {
      if ( $line_cnt == 0 ) {
        push @sql_data, $sth->{NAME};
      }
      else {
        my $clean_row_aref = $self->_clean_row( \@row );
        push @sql_data, $clean_row_aref;
      }
      $line_cnt++;
      if ( scalar @sql_data > 1000 ) {
        map { say {$out_fh} join( "\t", @$_ ); } @sql_data;
        @sql_data = ();
      }
    }
    $dbh->disconnect;
  }
}

sub _clean_row {
  my ( $self, $aref ) = @_;

  my @clean_array;
  for my $ele (@$aref) {
    if ( !defined($ele) ) {
      $ele = "NA";
    }
    elsif ( $ele eq "" ) {
      $ele = "NA";
    }
    push @clean_array, $ele;
  }
  return \@clean_array;
}

sub write_sql_data {
  my $self = shift;

  # statement
  $self->_logger->info( "sql cmd: " . $self->sql_statement ) if $self->verbose;

  # set directories
  my $local_dir = File::Spec->canonpath( $self->local_dir );
  my $cwd       = cwd();

  # set file names
  my $file_with_time   = $now_timestamp . "." . $self->local_file;
  my $target_file      = File::Spec->catfile( $local_dir, $file_with_time );
  my $symlink_original = File::Spec->catfile( ( $cwd, $local_dir ), $file_with_time );
  my $symlink_target = File::Spec->catfile( ( $cwd, $local_dir ), $self->local_file );

  # make target dir
  make_path($local_dir) if $self->act;

  my $sql_data = $self->_write_sql_data($target_file);

  # write data
  $self->_logger->info( "sql wrote data to: " . $target_file ) if $self->verbose;

  # link files
  if ( $self->act ) {
    chdir $local_dir || die "cannot change to $local_dir";

    if ( symlink $file_with_time, $self->local_file ) {
      $self->_logger->info("symlinked $symlink_original -> $symlink_target");
    }
    else {
      $self->_logger->error("could not symlink $symlink_original -> $symlink_target");
    }
    chdir $cwd || die "cannot change to $cwd";
  }
}

__PACKAGE__->meta->make_immutable;

1;
