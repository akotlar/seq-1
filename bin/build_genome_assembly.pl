#!/usr/bin/env perl

use 5.10.0;
use lib '/mnt/q22FSS/data/adsp/software/seq/lib'; 
use strict;
use warnings;
use Carp qw/ croak /;
use Getopt::Long;
use Path::Tiny;
use Pod::Usage;
use Log::Any::Adapter;
use YAML::XS qw/ LoadFile /;

use DDP;

use Seq::Build;

my (
  $yaml_config, $build_type,        $db_location,       $verbose,
  $no_bdb,      $help,              $wanted_chr,        $force,
  $debug,       $genome_hasher_bin, $genome_scorer_bin, $genome_cadd_bin,
);
$wanted_chr = 0;

# cmd to method
my %cmd_2_method = (
  genome        => 'build_genome_index',
  conserv       => 'build_conserv_scores_index',
  transcript_db => 'build_transcript_db',
  snp_db        => 'build_snp_sites',
  gene_db       => 'build_gene_sites',
);

my %bin_2_default = (
  genome_cadd_bin   => "bin/genome_cadd",
  genome_hasher_bin => "bin/genome_hasher",
  genome_scorer_bin => "bin/genome_scorer",
  ngene_bin => "bin/ngene",
);
my %bin_2_path = map { $_ => undef } ( keys %bin_2_default );

# usage
GetOptions(
  'c|config=s'   => \$yaml_config,
  't|type=s'     => \$build_type,
  'v|verbose'    => \$verbose,
  'h|help'       => \$help,
  'f|force'      => \$force,
  'd|debug'      => \$debug,
  'hasher=s'     => \$bin_2_path{genome_hasher_bin},
  'scorer=s'     => \$bin_2_path{genome_scorer_bin},
  'cadd=s'       => \$bin_2_path{genome_cadd_bin},
  'ngene=s'      => \$bin_2_path{ngene_bin},
  'wanted_chr=s' => \$wanted_chr,
);

if ($help) {
  Pod::Usage::pod2usage(1);
  exit;
}

unless ( defined $yaml_config and exists $cmd_2_method{$build_type} ) {
  Pod::Usage::pod2usage();
}

my $method = $cmd_2_method{$build_type};

# read config file to determine genome name for log and check validity
my $config_href = LoadFile($yaml_config);

p $config_href;

# location of the binaries
#   NOTE: precidence is cmd line > config file > default
for my $binary ( keys %bin_2_path ) {
  if ( exists $config_href->{$binary} ) {
    $bin_2_path{$binary} = $config_href->{$binary} unless $bin_2_path{$binary};
  }
  else {
    $bin_2_path{$binary} = $bin_2_default{$binary} unless $bin_2_path{$binary};
  }

  # get absolute path
  $bin_2_path{$binary} = path( $bin_2_path{$binary} )->absolute->stringify;

  # check the file exists
  unless ( -f $bin_2_path{$binary} ) {
    my $msg = sprintf( "ERROR: cannot find binary file: '%s'", $bin_2_path{$binary} );
    say $msg;
    exit(1);
  }
}

# get absolute path for YAML file and db_location
$yaml_config = path($yaml_config)->absolute->stringify;

my $builder_options_href = {
  configfile    => $yaml_config,
  genome_scorer => $bin_2_path{genome_scorer_bin},
  genome_hasher => $bin_2_path{genome_hasher_bin},
  genome_cadd   => $bin_2_path{genome_cadd_bin},
  ngene_bin     => $bin_2_path{ngene_bin},
  wanted_chr    => $wanted_chr,
  force         => $force,
  debug         => $debug,
};

if ( $method and $config_href ) {
  $wanted_chr = ($wanted_chr) ? $wanted_chr : 'all';
  # set log file
  my $log_name = join '.', 'build', $config_href->{genome_name}, $build_type,
    $wanted_chr, 'log';
  my $log_file = path(".")->child($log_name)->absolute->stringify;
  Log::Any::Adapter->set( 'File', $log_file );

  my $builder = Seq::Build->new_with_config($builder_options_href);

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
  --type <'genome', 'conserv', 'transcript_db', 'snp_db', 'gene_db'>
  [ --wanted_chr ]

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

=item B<-w>, B<--wanted_chr>

Wanted_chr: chromosome to build, if building gene or snp; will build all if not
specified.

=back

=head1 AUTHOR

Thomas Wingo

=head1 SEE ALSO

Seq Package

=cut
