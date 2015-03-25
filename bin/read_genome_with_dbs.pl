#!/usr/bin/env perl

use lib './lib';
use Getopt::Long;
use Modern::Perl qw/ 2013 /;
use Path::Tiny;
use Pod::Usage;
use Type::Params qw/ compile /;
use Types::Standard qw/ :type /;
use Log::Any::Adapter;
use Seq::Annotate;

if ( $ENV{PERL_MONGODB_DEBUG} ) {
  Log::Any::Adapter->set('Stdout');
}

use DDP;

my ( $chr_wanted, $pos_from, $pos_to, $db_location, $yaml_config, $verbose );
my ( $client, $db, $gan_db, $snp_db, $dbsnp_name, $dbgene_name, $help, $chr );
my (%tracks);

#
# usage
#
GetOptions(
  'c|chr=s'      => \$chr_wanted,
  'f|from=n'     => \$pos_from,
  't|to=n'       => \$pos_to,
  'c|config=s'   => \$yaml_config,
  'l|location=s' => \$db_location,
  'chr=s'        => \$chr,
  'v|verbose'    => \$verbose,
  'h|help'       => \$help,
);

if ($help) {
  Pod::Usage::pod2usage(1);
  exit;
}

unless ( defined $chr
  and defined $pos_from
  and defined $pos_to
  and defined $yaml_config
  and defined $db_location )
{
  Pod::Usage::pod2usage();
}

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

# 1-indexed coordinates
for ( my $i = $pos_from; $i <= $pos_to; $i++ ) {
  my $record = $assembly->annotate_site( $chr, $i );
  p $record;
}

__END__

=head1 NAME

read_genome - reads binary genome

=head1 SYNOPSIS

read_genome --chr <chr> --from <pos> --to <pos> --config <file> --locaiton <path>

=head1 DESCRIPTION

C<read_genome> takes a yaml configuration file and reads the binary genome
specified by that file. The binary genome is created by the Seq package.

=head1 OPTIONS

=over 8

=item B<-c>, B<--chr>

Chr: chromosome

=item B<-f>, B<--from>

From: absolute position (0-indexed) to start reading the genome.

=item B<-t>, B<--to>

To: absolute position (0-indexed) to stop reading the genome.

=item B<-c>, B<--config>

Config: A YAML genome assembly configuration file that specifies the various
tracks and data associated with the assembly. This is the same file that is
used by the Seq Package to build the binary genome without any alteration.

=item B<-l>, B<--location>

Location: This is the base directory that will be added to the location
information in the YAML configuration file that has a key specifying the
location of the binary index.

=back

=head1 AUTHOR

Thomas Wingo

=head1 SEE ALSO

Seq Package

=cut
