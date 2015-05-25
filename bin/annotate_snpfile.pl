#!/usr/bin/env perl

use 5.10.0;
use strict;
use warnings;

use lib './lib';
use Carp;
use Getopt::Long;
use File::Spec;
use Pod::Usage;
use Type::Params qw/ compile /;
use Types::Standard qw/ :type /;
use Log::Any::Adapter;
use YAML::XS qw/ LoadFile /;

use Seq;

my ( $snpfile, $yaml_config, $verbose, $help, $out_file, $force,
  $debug );

#
# usage
#
GetOptions(
  'c|config=s'   => \$yaml_config,
  's|snpfile=s'  => \$snpfile,
  'v|verbose'    => \$verbose,
  'h|help'       => \$help,
  'o|out=s'      => \$out_file,
  'f|force'      => \$force,
  'd|debug'      => \$debug,
);

if ($help) {
  Pod::Usage::pod2usage(1);
  exit;
}


unless ( $yaml_config
  and $snpfile
  and $out_file )
{
  Pod::Usage::pod2usage();
}

# sanity checks mostly now not needed, will be checked in Seq.pm using MooseX:Type:Path:Tiny
if ( -f $out_file && !$force ) {
  say "ERROR: '$out_file' already exists. Use '--force' switch to over write it.";
  exit;
}

<<<<<<< HEAD
# get absolute path
$out_file = File::Spec->rel2abs($out_file);

say "writing annotation data here: $out_file" if $verbose;
=======
# get absolute path not needed anymore, handled by coercison in Seq.pm, closer to where file is actually written
>>>>>>> 8f44ed26144d2374015c048e6309f0f8d19bef6c

# read config file to determine genome name for loging and to check validity of config
my $config_href = LoadFile($yaml_config)
  || die "ERROR: Cannot read YAML file - $yaml_config: $!\n";

# set log file
my $log_name = join '.', 'annotation', $config_href->{genome_name}, 'log';
my $log_file = File::Spec->rel2abs( ".", $log_name );
say "writing log file here: $log_file" if $verbose;
Log::Any::Adapter->set( 'File', $log_file );

# create the annotator
my $annotate_instance = Seq->new(
  {
    snpfile    => $snpfile,
    configfile => $yaml_config,
    out_file   => $out_file,
    debug      => $debug,
  }
);

# annotate the snp file
$annotate_instance->annotate_snpfile;

__END__

=head1 NAME

annotate_snpfile - annotates a snpfile using a given genome assembly specified
in a configuration file

=head1 SYNOPSIS

annotate_snpfile.pl --config <assembly config> --snp <snpfile> --locaiton <path> --out <file_ext>

=head1 DESCRIPTION

C<annotate_snpfile.pl> takes a yaml configuration file and snpfile and gives
the annotations for the sites in the snpfile.

=head1 OPTIONS

=over 8

=item B<-s>, B<--snp>

Snp: snpfile

=item B<-c>, B<--config>

Config: A YAML genome assembly configuration file that specifies the various
tracks and data associated with the assembly. This is the same file that is also
used by the Seq Package to build the binary genome without any alteration.

=item B<-l>, B<--location>

Location: This is the base directory for the location of the binary index.

=item B<-o>, B<--out>

Output directory: This is the output director.

=back

=head1 AUTHOR

Thomas Wingo

=head1 SEE ALSO

Seq Package

=cut
