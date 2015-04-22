#!/usr/bin/env perl

use 5.10.0;
use strict;
use warnings;

use lib './lib';
use Carp;
use Getopt::Long;
use Path::Tiny;
use Pod::Usage;
use Type::Params qw/ compile /;
use Types::Standard qw/ :type /;
use Log::Any::Adapter;
use YAML::XS qw/ LoadFile /;

use Seq;

my ( $snpfile, $yaml_config, $db_location, $verbose, $help, $out_file );

#
# usage
#
GetOptions(
  'c|config=s'   => \$yaml_config,
  's|snpfile=s'  => \$snpfile,
  'l|location=s' => \$db_location,
  'v|verbose'    => \$verbose,
  'h|help'       => \$help,
  'o|out=s'      => \$out_file,
);

if ($help) {
  Pod::Usage::pod2usage(1);
  exit;
}

unless ( $yaml_config
  and $db_location
  and $snpfile
  and $out_file )
{
  Pod::Usage::pod2usage();
}

# sanity check
if ( !-d $db_location ) {
  croak "ERROR: Expected '$db_location' to be a directory.";
} 
if ( !-f $snpfile ) {
  croak "ERROR: Expected '$snpfile' to be a file.";
}
if ( !-f $yaml_config ) {
  croak "ERROR: Expected '$yaml_config' to be a file.";
}
if ( !-f $out_file ) {
  croak "ERROR: '$out_file' already exists.";
}

$out_file = path($out_file)->absolute->stringify;

# read config file to determine genome name for log and check validity
my $config_href = LoadFile($yaml_config) 
  || croak "ERROR: Cannot read YAML file - $yaml_config\n";

# set log file
my $log_name = join '.', 'annotation', $config_href->{genome_name}, 'log';
my $log_file = path(".")->child($log_name)->absolute->stringify;
Log::Any::Adapter->set( 'File', $log_file );

my $annotate_instance = Seq->new(
  {
    snpfile    => $snpfile,
    configfile => $yaml_config,
    db_dir     => $db_location,
    out_file   => $out_file
  }
);

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

=back

=head1 AUTHOR

Thomas Wingo

=head1 SEE ALSO

Seq Package

=cut
