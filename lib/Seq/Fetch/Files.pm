package Seq::Fetch::Files;

use 5.10.0;
use Carp;
use File::Path;
use File::Spec;
use Moose;
use namespace::autoclean;
extends 'Seq::Config::GenomeSizedTrack';

has act     => ( is => 'ro', isa => 'Bool', );
has verbose => ( is => 'ro', isa => 'Bool', );

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

  my $script =
    join( "\n", "mkdir -p $local_dir", "cd $local_dir", @rsync_cmds, "cd -", "" );
  return $script;
}

sub say_process_files_script {
  my $self = shift;

  my $local_dir = File::Spec->canonpath( $self->local_dir );
  my $name      = $self->name;
  my @cmds;
  foreach my $method (qw( proc_init_cmds proc_chrs_cmds proc_clean_cmds )) {
    next unless $self->$method;
    push @cmds, "cd $local_dir";
    if ( $method eq "proc_chrs_cmds" ) # these cmds are looped over the files
    {
      my $chrs_aref = $self->genome_chrs;
      foreach my $chr (@$chrs_aref) {
        my %cmd_subs = (
          _add_file => '>>',
          _asterisk => '*',
          _chr      => $chr,
          _dir      => $name,
        );
        my $this_cmd = join( "\n", @{ $self->$method } );
        for my $sub ( keys %cmd_subs ) {
          $this_cmd =~ s/$sub/$cmd_subs{$sub}/g;
        }
        push @cmds, $this_cmd;
      }
      push @cmds, "cd -";
    }
    else {
      my $this_cmd = join( "\n", @{ $self->$method } );
      push @cmds, $this_cmd;
      push @cmds, "cd - ";
    }
  }
  my $script = (@cmds) ? join( "\n", @cmds ) : undef;
  return $script;
}

sub _get_rsync_opts {
  my $self    = shift;
  my $act     = $self->act;
  my $verbose = $self->verbose;
  my $opt     = "";
  if ($act) {
    if ($verbose) {
      $opt = "-avzP";
    }
    else {
      $opt = "-az";
    }
  }
  else {
    if ($verbose) {
      $opt = "-navzP";
    }
    else {
      $opt = "-naz";
    }
  }
  return $opt;
}

__PACKAGE__->meta->make_immutable;

1;
