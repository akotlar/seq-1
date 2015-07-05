#!/usr/bin/env perl

use 5.10.0;
use strict;
use warnings;

use lib './lib';
use Carp;
use DDP;
use Getopt::Long;
use File::Spec;
use Pod::Usage;
use Type::Params qw/ compile /;
use Types::Standard qw/ :type /;
use Log::Any::Adapter;
use YAML::XS qw/ LoadFile /;

use Seq::Annotate;

Log::Any::Adapter->set('Stdout');

my ( $snpfile, $yaml_file, $db_location, $verbose, $help, $out_file, $force,
  $debug );
my ( $wanted_chr, $pos_from, $pos_to );

#
# usage
#
GetOptions(
  'c|config=s'   => \$yaml_file,
  's|snpfile=s'  => \$snpfile,
  'l|location=s' => \$db_location,
  'v|verbose'    => \$verbose,
  'h|help'       => \$help,
  'o|out=s'      => \$out_file,
  'chr=s'        => \$wanted_chr,
  'f|from=s'     => \$pos_from,
  't|to=s'       => \$pos_to,
);

if ($help) {
  Pod::Usage::pod2usage(1);
  exit;
}

unless ( $yaml_file
  and $wanted_chr
  and defined $pos_from
  and $pos_to
  and -d $db_location )
{
  Pod::Usage::pod2usage();
}

# sanity check
unless ( -d $db_location ) {
  say "ERROR: Expected '$db_location' to be a directory.";
  exit;
}
unless ( -f $yaml_file ) {
  say "ERROR: Expected '$yaml_file' to be a file.";
  exit;
}

# clean up position
$pos_from =~ s/_|,//g;
$pos_to =~ s/_|,//g;

# sanity check position
if ( $pos_from >= $pos_to ) {
  say "Error: 'from' ('$pos_from') is greater than 'to' ('$pos_to')\n";
  exit;
}
# get abs file paths
$yaml_file   = File::Spec->rel2abs($yaml_file);
$db_location = File::Spec->rel2abs($db_location);

chdir($db_location) || croak "ERROR: cannot change to $db_location";

# read config file to determine genome name for loging and to check validity of config
my $config_href = LoadFile($yaml_file)
  || die "ERROR: Cannot read YAML file - $yaml_file: $!\n";

# set log file
my $log_name = join '.', 'annotation', $config_href->{genome_name}, 'log';
my $log_file = File::Spec->rel2abs( ".", $log_name );
say "writing log file here: $log_file" if $verbose;
Log::Any::Adapter->set( 'File', $log_file );

# create Seq::Annotate object
my $assembly = Seq::Annotate->new_with_config( { configfile => $yaml_file } );

# get ref annotations
my $abs_pos = $assembly->get_abs_pos( $wanted_chr, $pos_from )
  || croak "could not find location: $wanted_chr, $pos_from";
for my $i ( $pos_from .. $pos_to ) {
  my $href = $assembly->get_ref_annotation($abs_pos);
  $abs_pos++;
  p $href;
}

__END__

=head1 NAME

annotate_snpfile - annotates a snpfile using a given genome assembly specified
in a configuration file

=head1 SYNOPSIS

annotate_ref_site.pl --config <yaml config> --location <path/to/db> --chr <chr> --from <pos> --to <pos>

=head1 DESCRIPTION

C<annotate_snpfile.pl> takes a yaml configuration file and snpfile and gives
the annotations for the sites in the snpfile.

=head1 OPTIONS

=over 8

=item B<--chr>

Chromsome: "chr22"

=item B<--from>

From: start position

=item B<--to>

To: end position

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
