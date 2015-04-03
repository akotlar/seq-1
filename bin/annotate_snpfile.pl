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

use Seq;

if ( $ENV{PERL_MONGODB_DEBUG} ) {
  Log::Any::Adapter->set('Stdout');
}

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
  and -d $db_location
  and -f $snpfile
  and $out_file )
{
  Pod::Usage::pod2usage();
}

croak "expected '$yaml_config' to be a file" unless -f $yaml_config;

# need to give absolute path to avoid placing it in an odd location (e.g., where
# the genome is located)
$out_file = path($out_file)->absolute->stringify;

say
  qq{ snpfile => $snpfile, configfile => $yaml_config, db_dir => $db_location, out_file => $out_file };
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
