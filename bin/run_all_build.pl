#!/usr/bin/env perl
# Name:           run_all_build.pl
# Date Created:   Sun May 17 21:10:27 2015
# Date Modified:  Sun May 17 21:10:27 2015
# By:             TS Wingo
#
# Description:

use 5.10.0;
use strict;
use warnings;

use lib './lib';
use Carp;
use Getopt::Long;
use File::Spec;
use Path::Tiny;
use Pod::Usage;
use Type::Params qw/ compile /;
use Types::Standard qw/ :type /;
use Log::Any::Adapter;
use YAML::XS qw/ LoadFile /;

# variables
my ( $verbose, $act, $config_file, $out_ext, $location, $build_assembly );
my @type = qw/ genome conserv transcript_db snp_db gene_db /;

# get options
die
  "Usage: $0 [-v] [-a] -b <build_assembly script> -c <assembly config> -l location\n"
  unless GetOptions(
  'v|verbose'    => \$verbose,
  'a|act'        => \$act,
  'b|build=s'    => \$build_assembly,
  'c|config=s'   => \$config_file,
  'l|location=s' => \$location,
  ) and $config_file;
$verbose++ unless $act;

# clean path
$build_assembly = path($build_assembly)->absolute->stringify;
$config_file    = path($config_file)->absolute->stringify;
$location       = path($location)->absolute->stringify;

my $config_href = LoadFile($config_file);

for my $type (qw/ gene_db snp_db /) {
  for my $chr ( @{ $config_href->{genome_chrs} } ) {
    my $cmd =
      qq{$build_assembly --config $config_file --location $location --type $type --wanted_chr $chr};
    $cmd .= " --verbose" if $verbose;
    $cmd .= " --act"     if $act;
    my $file_name = Write_script( $type, $chr, $cmd );
    my $q_cmd = qq{qsub -v USER -v PATH -cwd -o $type.$chr.log -j y $file_name};
    say $q_cmd if $verbose;
    system $q_cmd if $act;
  }
}

sub Write_script {
  my ( $type, $chr, $cmd ) = @_;
  my $file_name = "$type.$chr.sh";
  my $out_fh = IO::File->new( $file_name, 'w' );
  say { $out_fh } join "\n", '#!bin/sh', $cmd;
  return $file_name;
}
