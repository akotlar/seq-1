#!/usr/bin/env perl

use lib './lib';
# use Coro;
use Carp qw/ croak /;
use Getopt::Long;
use Modern::Perl qw/ 2013 /;
use Path::Tiny;
use Pod::Usage;
use Type::Params qw/ compile /;
use Types::Standard qw/ :type /;
use Log::Any::Adapter ( 'File', 'build.log' );

use Seq::Build;

my ( $yaml_config, $db_location, $verbose, $help );

#
# usage
#
GetOptions(
  'c|config=s'   => \$yaml_config,
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

# get absolute path for YAML file and db_location
$yaml_config = path($yaml_config)->absolute->stringify;
$db_location = path($db_location)->absolute->stringify;

if ( -d $db_location ) {
  chdir($db_location) || croak "cannot change to dir: $db_location: $!\n";
}
else {
  croak "expected location of db to be a directory instead got: $db_location\n";
}

say qq{ configfile => $yaml_config, db_dir => $db_location };
my $assembly = Seq::Build->new_with_config( { configfile => $yaml_config } );

# threads
# {
#   my @coros;
#   for my $method (qw/ build_snp_sites build_gene_sites build_transcript_seq build_conserv_scores_index/) {
#     my $coro = async {
#       my $result;
#       unless ( $assembly->$method ) {
#         $result = "done with $method";
#       }
#       return $result;
#     };
#     push @coros, $coro;
#   }
#   $_->join for @coros;
#   $assembly->build_genome_index;
# }

#linear
{
  $assembly->build_snp_sites;
  say "done with building snps";
  $assembly->build_gene_sites;
  say "done with building genes";
  $assembly->build_genome_index;
  say "done building genome index";
}

__END__

=head1 NAME

build_genome_assembly - builds a binary genome assembly

=head1 SYNOPSIS

build_genome_assembly --config <file> --locaiton <path>

=head1 DESCRIPTION

C<build_genome_assembly.pl> takes a yaml configuration file and reads raw genomic data
that has been previously downloaded into the 'raw' folder to create the binary
index of the genome and assocated annotations in the mongodb instance.

=head1 OPTIONS

=over 8

=item B<-c>, B<--config>

Config: A YAML genome assembly configuration file that specifies the various
tracks and data associated with the assembly. This is the same file that is
used by the Seq Package to annotate snpfiles.

=item B<-l>, B<--location>

Location: Base location of the raw genomic information used to build the
annotation index.

=back

=head1 AUTHOR

Thomas Wingo

=head1 SEE ALSO

Seq Package

=cut
