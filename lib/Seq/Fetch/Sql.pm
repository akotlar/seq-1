package Seq::Fetch::Sql;

use 5.10.0;
use Carp;
use Cwd;
use DBI;
use File::Path;
use File::Spec;
use Moose;
use namespace::autoclean;
use Time::localtime;

extends 'Seq::Config::SparseTrack';
with 'Seq::Role::IO';

my $now_timestamp = sprintf( "%d-%02d-%02d",
  eval( localtime->year() + 1900 ),
  eval( localtime->mon() + 1 ),
  localtime->mday() );

has genome_name => ( is => 'ro', isa => 'Str', required => 1, );
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
has act      => ( is => 'ro', isa => 'Int' );
has verbose  => ( is => 'ro', isa => 'Int' );

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

sub get_sql_aref {

  my $self = shift;

  # get data
  my $track_statement = $self->sql_statement;

  # get connection handle
  my $dbh = $self->dbh;

  # prepare and execute mysql command
  my $sth = $dbh->prepare($track_statement) or die $dbh->errstr;
  my $rc = $sth->execute or die $dbh->errstr;

  # retrieve data
  my @sql_data;
  while ( my @row = $sth->fetchrow_array ) {
    my @clean_row = map {
      if ( !defined($_) ) {
        "NA";
      }
      elsif ( $_ eq "" ) {
        "NA";
      }
      else {
        $_;
      }
    } @row;
    push @sql_data, \@row;
  }
  $dbh->disconnect;
  return \@sql_data;
}

sub write_sql_data {
  my $self = shift;

  # set directories
  my $dir = File::Spec->canonpath( $self->local_dir );
  my $cwd = cwd();

  # set file names
  my $file_with_time   = $now_timestamp . "." . $self->local_file;
  my $target_file      = File::Spec->catfile( $dir, $file_with_time );
  my $symlink_original = File::Spec->catfile( ( $cwd, $dir ), $file_with_time );
  my $symlink_target   = File::Spec->catfile( ( $cwd, $dir ), $self->local_file );

  # make target dir
  File::Path->make_path($dir);

  my $out_fh = $self->get_write_fh($target_file);

  # get data
  my $sql_data = $self->get_sql_aref;

  # write data
  map { say $out_fh join( "\t", @$_ ); } @$sql_data;

  # link files and return success
  return symlink $symlink_original, $symlink_target;
}

__PACKAGE__->meta->make_immutable;

1;
