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

use Seq::Build;

my ( $yaml_config, $build_type, $db_location, $verbose, $no_bdb, $help );

my $genome_hasher_bin = './genome_hasher';
my $genome_scorer_bin = './genome_scorer';

# cmd to method
my %cmd_2_method = (
  genome        => 'build_genome_index',
  conserv       => 'build_conserv_scores_index',
  transcript_db => 'build_transcript_db',
  snp_db        => 'build_snp_sites',
  gene_db       => 'build_gene_sites',
);

# usage
GetOptions(
  'c|config=s'   => \$yaml_config,
  'l|location=s' => \$db_location,
  't|type=s'     => \$build_type,
  'v|verbose'    => \$verbose,
  'n|no_bdb'     => \$no_bdb,
  'h|help'       => \$help,
  'hasher=s'     => \$genome_hasher_bin,
  'scorer=s'     => \$genome_scorer_bin,
);

if ($help) {
  Pod::Usage::pod2usage(1);
  exit;
}

my $method //= $cmd_2_method{$build_type};

unless ( defined $yaml_config
  and defined $db_location
  and defined $method )
{
  Pod::Usage::pod2usage();
}

# get absolute path for YAML file and db_location
$yaml_config       = path($yaml_config)->absolute->stringify;
$db_location       = path($db_location)->absolute->stringify;
$genome_hasher_bin = path($genome_hasher_bin)->absolute->stringify;
$genome_scorer_bin = path($genome_scorer_bin)->absolute->stringify;

if ( -d $db_location ) {
  chdir($db_location) || croak "cannot change to dir: $db_location: $!\n";
}
else {
  croak "expected location of db to be a directory instead got: $db_location\n";
}

# read config file to determine genome name for log and check validity
my $config_href = LoadFile($yaml_config);

my $builder_options_href = {
  configfile    => $yaml_config,
  no_bdb_insert => $no_bdb,
  genome_scorer => $genome_scorer_bin,
  genome_hasher => $genome_hasher_bin
};

my $builder = Seq::Build->new_with_config($builder_options_href);

if ( $method and $config_href ) {

  # set log file
  my $log_name = join '.', 'build', $config_href->{genome_name}, $build_type, 'log';
  my $log_file = path($db_location)->child($log_name)->absolute->stringify;
  Log::Any::Adapter->set( 'File', $log_file );

  # build encoded genome, gene and snp site databases
  $builder->$method;
  say "done: $build_type";
}

__END__

=head1 NAME

build_genome_assembly - builds a binary genome assembly

=head1 SYNOPSIS

build_genome_assembly
  --config <file>
  --locaiton <path>
  --type <'genome', 'conserv', 'transcript_db', 'snp_db', 'gene_db'>

=head1 DESCRIPTION

C<build_genome_assembly.pl> takes a yaml configuration file and reads raw genomic
data that has been previously downloaded into the 'raw' folder to create the binary
index of the genome and assocated annotations in the mongodb instance.

=head1 OPTIONS

=over 8

=item B<-t>, B<--type>

Type: A general command to start building; genome, conserv, transcript_db, gene_db
or snp_db.

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
