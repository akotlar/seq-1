#!/usr/bin/env perl
# Name:           get_node_annotation_data.pl
# Date Created:   Wed Jun 17 09:58:44 2015
# Date Modified:  Wed Jun 17 09:58:44 2015
# By:             TS Wingo
#
# Description:

use 5.10.0;
use strict;
use warnings;
use Getopt::Long;
use Cwd;
use File::Spec;
use IO::File;
use DDP;

my ( $verbose, $act, $source_dir, $destination_dir );

# get options
die "Usage: $0 [-v] [-a] -s <source dir> -t <destination dir>\n"
  unless GetOptions(
  'v|verbose'       => \$verbose,
  'a|act'           => \$act,
  's|source=s'      => \$source_dir,
  'd|destination=s' => \$destination_dir,
  )
  and $source_dir
  and $destination_dir;
$verbose++ unless $act;

my $wd              = cwd();
my @nodes           = map { sprintf( "%02d", $_ ) } ( 1 .. 4 );
my $out_script_file = File::Spec->catfile( $wd, "rsync_tmp.$$.sh" );
my $out_script_fh   = IO::File->new( $out_script_file, 'w' )
  or die "$out_script_file: $!\n";
$destination_dir = File::Spec->rel2abs($destination_dir);
my $rsync_opt = "-aP";
$rsync_opt .= "n" unless $act;
$rsync_opt .= "v" if $verbose;

my $script_txt = qq{
#!/bin/sh
cd $wd
rsync $rsync_opt $source_dir $destination_dir
};

say {$out_script_fh} $script_txt;

for my $node (@nodes) {
  my $cmd = qq{dsh -w -m node$node "sh $out_script_file"};
  say $cmd if $verbose;
  system $cmd if $act;
}

unlink $out_script_file;

print
  ">>> IF NOTHING SEEMS TO BE WORKING MAKE SURE YOUR ARE RUNNING THIS FROM THE HEAD NODE (node00). <<<\n\n";
