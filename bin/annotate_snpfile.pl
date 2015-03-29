#!/usr/bin/env perl

use lib './lib';
use Getopt::Long;
use Modern::Perl qw/ 2013 /;
use Path::Tiny;
use Pod::Usage;
use Type::Params qw/ compile /;
use Types::Standard qw/ :type /;
use Log::Any::Adapter;

use Seq;

if ( $ENV{PERL_MONGODB_DEBUG} ) {
  Log::Any::Adapter->set('Stdout');
}

use DDP;

my ($snpfile, $yaml_config, $db_location, $verbose, $help);

#
# usage
#
GetOptions(
  'c|config=s'   => \$yaml_config,
  's|snpfile=s'  => \$snpfile,
  'l|location=s' => \$db_location,
  'v|verbose'    => \$verbose,
  'h|help'       => \$help,
);

if ($help) {
  Pod::Usage::pod2usage(1);
  exit;
}

unless ( defined $yaml_config
  and defined $db_location )
{
  Pod::Usage::pod2usage();
}

say qq{ snpfile => $snpfile, configfile => $yaml_config, db_dir => $db_location };
my $annotate_instance = Seq->new( { snpfile => $snpfile, configfile => $yaml_config, db_dir => $db_location } );

$annotate_instance->annotate_snpfile;

__END__

=head1 NAME

annotate_snpfile - annotates a snpfile using a given genome assembly specified
in a configuration file

=head1 SYNOPSIS

annotate_snpfile.pl --snp <snpfile> --config <file> --locaiton <path>

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
