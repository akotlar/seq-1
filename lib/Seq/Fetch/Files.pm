package Seq::Fetch::Files;

=head1 DESCRIPTION

  @class Seq::Fetch::Files
  This class fetches raw files from remote locations (e.g., UCSC genome browser
  rsync server) that are required to build the genome assembly sepcified in the
  configuration file.

  @example

Used in:
=for :list
* Seq::Fetch

Extended by: None

=cut

use 5.10.0;
use Carp;
use File::Path;
use File::Spec;
use File::Rsync;

use Moose;
use namespace::autoclean;

extends 'Seq::Config::GenomeSizedTrack';

has act     => ( is => 'ro', isa => 'Bool', );
has verbose => ( is => 'ro', isa => 'Bool', );
has rsync_bin =>
  ( is => 'ro', isa => 'Str', required => 1, builder => '_build_rsync_bin', );

sub _build_rsync_bin {
  my $self          = shift;
  my %rsync_loc_for = (
    loc_1 => '/opt/local/bin/rsync',
    loc_2 => '/usr/local/bin/rsync',
    loc_3 => '/usr/bin/rsync'
  );
  for my $sys ( sort keys %rsync_loc_for ) {
    return $rsync_loc_for{$sys} if -f $rsync_loc_for{$sys};
  }
  return;
}

sub fetch_files {

  my $self = shift;

  my $name              = $self->name;
  my $remote_files_aref = $self->remote_files;

  # get rsync cmd and opts
  my %rsync_opt = ( compress => 1, 'rsync-path' => $self->rsync_bin );
  $rsync_opt{verbose}++ if $self->verbose;
  $rsync_opt{'dry-run'}++ unless $self->act;

  my $rsync_obj = File::Rsync->new( \%rsync_opt );

  # prepare directories
  my $local_dir = File::Spec->rel2abs( $self->local_dir );
  # my $remote_dir = $self->remote_dir;

  # File::Rsync expects host:dir format for remote files (if needed)
  # $remote_dir =~ s/\//::/xm unless ( $remote_dir =~ m/::/xm );
  my @remote_src  = split /\//, $self->remote_dir;
  my $remote_host = $remote_src[0] . ":";
  my $remote_dir  = join "/", @remote_src[ 1 .. $#remote_src ];

  # make local dir (if needed)
  mkpath $local_dir unless -d $local_dir;

  # fetch files
  for my $file ( @{$remote_files_aref} ) {
    my $this_remote_file = File::Spec->catfile( $remote_dir, $file );
    my $cmd_href =
      { srchost => $remote_host, source => $this_remote_file, dest => $local_dir };
    my $cmd = $rsync_obj->getcmd($cmd_href);
    my $cmd_txt = join " ", @$cmd;
    $self->_logger->info( "rsync cmd: " . $cmd_txt ) if $self->verbose;
    system $cmd_txt if $self->act || $self->_logger->error( "failed: " . $cmd_txt );
  }
}

__PACKAGE__->meta->make_immutable;

1;
