#!/usr/bin/env perl

use 5.10.0;
use strict;
use warnings;
use lib './lib';
use Carp qw/ croak /;
use Getopt::Long;
use Path::Tiny;
use Pod::Usage;
use Type::Params qw/ compile /;
use Types::Standard qw/ :type /;
use Log::Any::Adapter;
use YAML::XS qw/ LoadFile /;

use Seq::Fetch;

my ($yaml_config, $db_location, $verbose, $help, $act);

# usage
GetOptions(
  'c|config=s'   => \$yaml_config,
  'l|location=s' => \$db_location,
  'v|verbose'    => \$verbose,
  'h|help'       => \$help,
  'a|act'        => \$act,
);

if ($help) {
  Pod::Usage::pod2usage(1);
  exit;
}

unless ( defined $yaml_config and $db_location ) {
  Pod::Usage::pod2usage();
}

# get absolute path for YAML file and db_location
$yaml_config       = path($yaml_config)->absolute->stringify;
$db_location       = path($db_location)->absolute->stringify;

if ( -d $db_location ) {
  chdir($db_location) || croak "cannot change to dir: $db_location: $!\n";
}
else {
  croak "expected location of db to be a directory instead got: $db_location\n";
}

# read config file to determine genome name for log and check validity
my $config_href = LoadFile($yaml_config);

my $fetch_options_href = {
  configfile => $yaml_config,
  act => $act,
  verbose => $verbose
};

# set log file
my $log_name = join '.', 'fetch', $config_href->{genome_name}, 'log';
my $log_file = path($db_location)->child($log_name)->absolute->stringify;
Log::Any::Adapter->set( 'File', $log_file );

my $fetch_obj = Seq::Fetch->new_with_config( $fetch_options_href );

# fetch remote files
$fetch_obj->fetch_genome_size_tracks;

# fetch sql data
$fetch_obj->fetch_sparse_tracks;

__END__

=head1 NAME

fetch_assembly_files - fetches files for assembly annotation

=head1 SYNOPSIS

fetch_assembly_files
  --config <file>
  --locaiton <path>
  [ --act ]
  [ --verbose ]

=head1 DESCRIPTION

C<fetch_assembly_files.pl> takes a yaml configuration file and fetches the
specified raw genomic data.

=head1 OPTIONS

=over 8

=item B<-a>, B<--act>

Act: Optionally fetches (or performs a dry-run).

=item B<-c>, B<--config>

Config: A YAML genome assembly configuration file that specifies the various
tracks and data associated with the assembly. This is the same file that is
used by the Seq Package to annotate snpfiles.

=item B<-l>, B<--location>

Location: Base location of the raw genomic information used to build the
annotation index.

=item B<-v>, B<--verbose>

Verbose: Optionally writes comments to log file.

=back

=head1 AUTHOR

Thomas Wingo

=head1 SEE ALSO

Seq Package

=cut
