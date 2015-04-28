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

use DDP;

use Seq;

Log::Any::Adapter->set('Stdout');

my ( $snpfile, $yaml_config, $db_location, $verbose, $help, $out_file );
my ( $wanted_chr, $pos_from, $pos_to );

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
  'chr=s'        => \$wanted_chr,
  'f|from=n'     => \$pos_from,
  't|to=n'       => \$pos_to,
);

if ($help) {
  Pod::Usage::pod2usage(1);
  exit;
}

unless ( $yaml_config
  and defined $wanted_chr
  and defined $pos_from
  and defined $pos_to
  and -d $db_location )
{
  Pod::Usage::pod2usage();
}

croak "expected '$yaml_config' to be a file" unless -f $yaml_config;

# need to give absolute path to avoid placing it in an odd location (e.g., where
# the genome is located)
#$out_file = path($out_file)->absolute->stringify;

# clean up position
$pos_from =~ s/\_|\,//g;
$pos_to =~ s/\_|\,//g;

# sanity check position
if ( $pos_from >= $pos_to ) {
  say "Error: 'from' ('$pos_from') is greater than 'to' ('$pos_to')\n";
  exit;
}

# get absolute paths for files
$db_location = path($db_location)->absolute;
$yaml_config = path($yaml_config)->absolute;

# change to the root dir of the database
chdir($db_location) || die "cannot change to $db_location: $!";

# load configuration file
my $assembly = Seq::Annotate->new_with_config( { configfile => $yaml_config } );

for my $i ( $pos_from .. $pos_to ) {
  my $abs_pos = $assembly->get_abs_pos( $wanted_chr, $i );
  my $href = $assembly->get_ref_annotation($abs_pos);
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
