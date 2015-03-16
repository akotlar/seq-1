#!/usr/bin/env perl
# Name:           make_fake_genome.pl
# Date Created:   Wed Mar 11 10:22:55 2015
# Date Modified:  Wed Mar 11 10:22:55 2015
# By:             TS Wingo
#
# Description: 
#   1. select a real gene from each chromosome
#   2. shift coordinates so that the gene is the 1st gene on the chromsome
#   3. write new gene coordinates in the knownGene format
#   4. write a bedfile with real genome coordinates that should be 
#      used to grab real sequences as tests for the annotation
#   5. write fake conservation scores based on lengths of the sequences 
#      grabbed.
#
#   TODO: 
#     - change offsets so we grab flanking regions around each gene
#

use 5.10.0;
use strict;
use warnings;
use DBI;
use Getopt::Long;
use File::Spec;
use File::Path qw( make_path );
use IO::File;
use IO::Compress::Gzip qw( gzip $GzipError );
use IO::Uncompress::Gunzip qw( $GunzipError );
use Scalar::Util qw( looks_like_number );
use YAML qw(Dump Bless);
use DDP;

#
# variables
#
my ( $verbose, $act, $out_ext );
my $dir = 'sandbox';
my $twobit2fa_prog = 'twoBitToFa';
my $twobit_genome  = 'hg38.2bit';
my $genome = 'hg38';
my $dsn    = "DBI:mysql:host=genome-mysql.cse.ucsc.edu;database=$genome";
my $dbh    = DBI->connect($dsn, "genome", "")
  or die "cannot connect to $dsn";

#
# get options
#
die join ("\n\t", "Usage: $0 [-v] [-a]", "-d <dir to create data, default = $dir>",
          "-g <genome, default = $genome>",
          "--twoBitToFa_prog <binary, default = $twobit2fa_prog>",
          "--twoBit_genome <2bit file, default = $twobit_genome", )
  unless GetOptions(
                    'v|verbose'  => \$verbose,
                    'a|act'      => \$act,
                    'g|genome=s' => \$genome,
                    'o|out=s'    => \$out_ext,
                    'twoBitToFa_prog=s' => \$twobit2fa_prog,
                    'twoBit_genome=s' => \$twobit_genome,
                    'd|dir=s'          => \$dir
                   )
  and $out_ext
  and $genome
  and $twobit2fa_prog
  and $twobit_genome
  and $dir;
$verbose++ unless $act;

# change dir to directory where we'll download data
chdir $dir or die "cannot change into $dir";

# get abs path to 2bit file 
#   going to assume twoBitToFa is in path
unless (File::Spec->file_name_is_absolute( $twobit_genome ))
{
  my ($vol, $dir, $file) = File::Spec->splitpath( $twobit_genome );
  $twobit_genome = File::Spec->rel2abs( $dir, $file );
}

# make dirs
my %out_dirs = ( raw => "$genome/raw", seq => "$genome/raw/seq", 
  gene => "$genome/raw/gene", phyloP => "$genome/raw/phyloP",
  phastCons => "$genome/raw/phastCons", bed => "$genome/raw", );
%out_dirs = map { $_ => File::Spec->rel2abs( File::Spec->canonpath($out_dirs{$_}) ) } keys %out_dirs;
map { make_path( $out_dirs{$_} ) } keys %out_dirs;

# make files
my %out_files = ( gene => 'knownGene.txt.gz', phyloP => 'phyloP.txt.gz', 
  phastCons => 'phastCons.txt.gz', bed => "$out_ext.bed.gz" );
%out_files = map { $_ => File::Spec->catfile( $out_dirs{$_}, $out_files{$_} ) } keys %out_files;

# open file handles
my %out_fhs = map { $_ => IO::Compress::Gzip->new( $out_files{$_} ) } keys %out_files;

# print out for debugging
p %out_dirs;
p %out_files;
p %out_fhs;
p $twobit_genome;

my @chrs = map { "chr$_" } (1 .. 22, 'M', 'X', 'Y');
my (%header, %found_chr, %chr_len);

# change into seq dir to write files
chdir $out_dirs{seq} || die "cannot change dir $out_dirs{seq}\n";
for my $chr (@chrs)
{
    my $sth = $dbh->prepare(
        qq{
    SELECT * 
    FROM $genome.knownGene 
    LEFT JOIN $genome.kgXref  
    ON $genome.kgXref.kgID = $genome.knownGene.name
    WHERE ($genome.knownGene.chrom = '$chr') 
    AND ($genome.knownGene.cdsStart != $genome.knownGene.cdsEnd) 
    LIMIT 1
    }
      )
      or die $dbh->errstr;
    my $rc = $sth->execute() or die $dbh->errstr;
    my @header = @{$sth->{NAME}};
    %header = map { $header[$_] => $_ } (0 .. $#header) unless %header;
    while (my @row = $sth->fetchrow_array)
    {
        my %data = map { $_ => $row[$header{$_}] } keys %header;
        if ($data{cdsEnd} != $data{cdsStart}
            && !exists $found_chr{$data{chrom}})
        {
            #
            # save in bed file (real coordinates)
            #
            say { $out_fhs{bed} } join("\t",
                              $data{chrom}, $data{txStart},
                              $data{txEnd}, $data{name});
            my @exon_starts = split(/\,/, $data{exonStarts});
            my @exon_ends   = split(/\,/, $data{exonEnds});
            my (@new_exon_ends, @new_exon_starts);
            my $txStart = $data{txStart} - 1;
            for (my $i = 0 ; $i < @exon_starts ; $i++)
            {
                my $new_start = $exon_starts[$i] - $txStart;
                push @new_exon_starts, $new_start;
                my $new_ends = $exon_ends[$i] - $txStart;
                push @new_exon_ends, $new_ends;
            }
            $data{txEnd}    -= $txStart;
            $data{txStart}  -= $txStart;
            $data{cdsStart} -= $txStart;
            $data{cdsEnd}   -= $txStart;
            $data{exonStarts} = join(",", @new_exon_starts);
            $data{exonEnds}   = join(",", @new_exon_ends);

            my $length = Get_gz_seq( $chr, $data{txStart}, $data{txEnd} );
            $found_chr{$data{chrom}} = \%data;

            die "expected lengths to match" 
              unless $length == ($data{txEnd} - $data{txStart});
            $chr_len{$chr} = $data{txEnd} - $data{txStart};
        }
    }
}
chdir $out_dirs{raw} or die "cannot change dir $out_dirs{raw}\n";
p %found_chr;

# print fake knownGene data
say { $out_fhs{gene} } join("\t", (map { $_ } (sort keys %header)));
for my $chr (sort keys %found_chr)
{
  say { $out_fhs{gene} }
  join("\t", (map { $found_chr{$chr}{$_} } (sort keys %header)));
}

# print fake conservation data
for my $chr (@chrs)
{
  for (my $i = 0; $i < $chr_len{$chr}; $i++)
  {
    say { $out_fhs{phastCons} } join("\t", $chr, eval($i + 1), rand(1)) if rand(1) > 0.5;
    say { $out_fhs{phyloP} }    join("\t", $chr, eval($i + 1), eval ( rand(60) - 30 )) 
      if rand(1) > 0.5;
  }
}

# returns length of sequence
sub Get_gz_seq { 
  my ($chr, $start, $end) = @_;
  die "error processing Get_gz_seq() arguments @_"
    unless $chr and $start and $end;

  # grab sequence
  my $fa_file = qq{test_$chr.fa};
  my $cmd = qq{$twobit2fa_prog $twobit_genome:$chr:$start-$end $fa_file};
  say $cmd if $verbose;
  system $cmd;

  # check we got sequence
  die "error grabbing sequence with cmd:\n\t$cmd\n" unless ( -s "test_$chr.fa" );

  # get length of sequence
  #   and gzip file
  my $length = 0;
  my $fa_fh = IO::File->new( $fa_file, 'r' );
  my $gz_fh = IO::Compress::Gzip->new( "$fa_file.gz" ) 
    or die "gzip failed: $GzipError\n";
  while (<$fa_fh>)
  {
    chomp $_;
    $length += length $_ unless ($_ =~ m/\A>/);
    say { $gz_fh } $_;
  }
  say join(" ", $chr, "=>", $length) if $verbose;
  return $length;
}
  



