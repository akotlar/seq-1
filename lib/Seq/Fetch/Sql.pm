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
use DBI;
use Moose;
use namespace::autoclean;
use Time::localtime;
use Data::Dump qw/ dump /;

extends 'Seq::Config::SparseTrack';
with 'Seq::Role::IO';

# time stamp
my $year          = localtime->year() + 1900;
my $mos           = localtime->mon() + 1;
my $day           = localtime->mday;
my $now_timestamp = sprintf( "%d-%02d-%02d", $year, $mos, $day );

has act   => ( is => 'ro', isa => 'Bool', default => 0 );
has debug => ( is => 'ro', isa => 'Bool', default => 0 );
has dsn   => ( is => 'ro', isa => 'Str', required => 1, default => "DBI:mysql" );
has host => (
  is       => 'ro',
  isa      => 'Str',
  required => 1,
  default  => "genome-mysql.cse.ucsc.edu"
);
has user     => ( is => 'ro', isa => 'Str', required => 1, default => "genome" );
has password => ( is => 'ro', isa => 'Str', );
has port     => ( is => 'ro', isa => 'Int', );
has socket   => ( is => 'ro', isa => 'Str', );


=function sql_statement (private,)

Construction-time @property sql_statement modifier

@requires:

=begin :list
* @property {Str} $self->type

    @values:

    =begin :list
    1. 'snp'
    2. 'gene'
    =end :list

* @property {ArrarRef<Str>} $self->features
* @property {Str} $self->sql_statement (returned by $self->$orig(@_) )
* @param {Str} @snp_track_fields (global)
=end :list

@return {Str}

=cut

around 'sql_statement' => sub {
  my $orig     = shift;
  my $self     = shift;
  my $new_stmt = "";

  # handle blank sql statements
  return unless $self->$orig(@_);

  # make substitutions into the sql statements
  if ( $self->type eq 'snp' ) {
    my $snp_table_fields_str = join( ", ", @{ $self->snp_track_fields},
      @{ $self->features } );

    # \_ matches the character _ literally
    # snp matches the characters snp literally (case sensitive)
    # \_ matches the character _ literally

    # NOTE: the following just defines the perl regex spec and could be removed.
    # fields matches the characters fields literally (case sensitive)
    # x modifier: extended. Spaces and text after a # in the pattern are ignored
    # m modifier: multi-line. Causes ^ and $ to match the begin/end of each line
    #             (not only begin/end of string)
    if ( $self->$orig(@_) =~ m/\_snp\_fields/xm ) {
      # substitute _snp_fields in statement for the comma separated string of
      # snp_track_fields and SparseTrack features
      ( $new_stmt = $self->$orig(@_) ) =~ s/\_snp\_fields/$snp_table_fields_str/xms;
    }
    elsif ( $self->$orig(@_) =~ m/_asterisk/xm ) {
      ( $new_stmt = $self->$orig(@_) ) =~ s/\_asterisk/\*/xm;
    }
  }
  elsif ( $self->type eq 'gene' ) {
    my $gene_table_fields_str = join( ", ", @{$self->gene_track_fields},
      @{ $self->features } );

    if ( $self->$orig(@_) =~ m/\_gene\_fields/xm ) {
      ( $new_stmt = $self->$orig(@_) ) =~ s/\_gene\_fields/$gene_table_fields_str/xms;
    }
  }
  return $new_stmt;
};

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
  $dsn .= ":" . $self->name;
  $dsn .= ";host=" . $self->host if $self->host;
  $dsn .= ";port=" . $self->port if $self->port;
  $dsn .= ";mysql_socket=" . $self->port_num if $self->socket;
  $dsn .= ";mysql_read_default_group=client";
  my %conn_attrs = ( RaiseError => 1, PrintError => 0, AutoCommit => 0 );
  return DBI->connect( $dsn, $self->user, $self->password, \%conn_attrs );
}

sub _fetch_remote_data {

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

sub write_remote_data {
  my $self = shift;

  say $self->type;
  say $self->sql_statement;
  say $self->features;

  # statement
  my $msg = "sql cmd: " . $self->sql_statement;
  $self->_logger->info( $msg );
  say $msg if $self->debug;

  exit;

  # set directories
  $self->genome_raw_dir->mk_path unless -d $self->genome_raw_dir;

  # set file names
  my @local_files = $self->all_local_files;

  # just use the 1st one if we're asked to download data - the rationale for
  # having a list of files is that sometimes the data is alreadya list of files
  my $timestamp_name = sprintf( "%s.%s", $now_timestamp, $local_files[0]->basename);
  my $target_file = $self->genome_raw_dir->child->($self->type)->child($timestamp_name);
  my $master_file = $local_files[0];

  # fetch data
  my $sql_data = $self->_fetch_remote_data($target_file);

  # write data
  $msg = sprintf( "wrote remote data to: %s", $target_file );
  $self->_logger->info($msg);
  say $msg if $self->debug;

  # link files
  if ( $self->act ) {
    my $msg = sprintf( "symlink %s -> %s", $target_file->absolute->stringify,
      $master_file->absolute->stringify );
    if ( symlink $target_file->absolute->stringify, $master_file->absolute->stringify ) {

      $self->_logger->info($msg);
    }
    else {
      my $error_msg = "could not " . $msg;
      $self->_logger->error($error_msg);
    }
  }
}

__PACKAGE__->meta->make_immutable;

1;
