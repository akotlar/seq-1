#!/usr/bin/env perl
# Name:           make_fake_genome.pl
# Date Created:   Wed Mar 11 10:22:55 2015
# Date Modified:  2015-03-16
# By:             TS Wingo
#
# Description: Prepare fake genomic data using single genes from each
#              chromosomes; write appropriate files to correct place in
#              the directory tree.
#
#   1. select a real coding gene from each chromosome, which will become the
#       entire chromsome in the fake genome
#   2. use 2bit file and twoBitToFa to get genomic sequence and write as a
#       gzipped file for each chromosome
#   3. shift genetic coordinates for each transcript to reflect the single
#       transcript as the entire test chromosome
#   4. write genomic transcripts after UCSC's knownGene table
#   5. write fake conservation scores - phyloP and phastCons
#   6. write fake snps that occur ~1% of the genome after UCSC's snp tables
#
#   TODO:
#     - change offsets so we grab flanking regions around each gene
#     - use YAML file to override the chromosome names hard coded into this
#       script (Matthew)
#     - add fake data for clinvar (Matthew)
#     - add fake data for cad score (Matthew) and haploinsufficiency (Alex)
#     - accomidate species without known SNPs ()
#     - make a test "snpfile.txt" (Matthew)

use 5.10.0;
use strict;
use warnings;
use DBI;
use Getopt::Long;
use File::Spec;
use File::Path qw/ make_path /;
use IO::File;
use IO::Compress::Gzip qw/ gzip $GzipError /;
use IO::Uncompress::Gunzip qw/ $GunzipError /;
use List::Util qw/ shuffle /;
use Scalar::Util qw/ looks_like_number /;
use YAML qw/ Dump /;
use DDP;

#
# variables
#
my ($verbose, $act, $out_ext, %snpfile_sites);
my $dir            = 'sandbox';
my $twobit2fa_prog = 'twoBitToFa';
my $twobit_genome  = 'hg38.2bit';
my $genome         = 'hg38';
my $dsn = "DBI:mysql:host=genome-mysql.cse.ucsc.edu;database=$genome";
my $dbh = DBI->connect($dsn, "genome", "")
  or die "cannot connect to $dsn";

#
# get options
#
die join("\n\t",
         "Usage: $0 [-v] [-a]",
         "-d <dir to create data, default = $dir>",
         "-g <genome, default = $genome>",
         "--twoBitToFa_prog <binary, default = $twobit2fa_prog>",
         "--twoBit_genome <2bit file, default = $twobit_genome",
         "--out <out extension>"
        )
  unless GetOptions(
                    'v|verbose'         => \$verbose,
                    'a|act'             => \$act,
                    'g|genome=s'        => \$genome,
                    'o|out=s'           => \$out_ext,
                    'twoBitToFa_prog=s' => \$twobit2fa_prog,
                    'twoBit_genome=s'   => \$twobit_genome,
                    'd|dir=s'           => \$dir
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
unless (File::Spec->file_name_is_absolute($twobit_genome))
{
  my ($vol, $dir, $file) = File::Spec->splitpath($twobit_genome);
  $twobit_genome = File::Spec->rel2abs($dir, $file);
}

# make dirs
my %out_dirs = (
                bed       => "$genome/raw",
                snpfile   => "$genome/raw",
                raw       => "$genome/raw",
                seq       => "$genome/raw/seq",
                snp       => "$genome/raw/snp",
                gene      => "$genome/raw/gene",
                phyloP    => "$genome/raw/phyloP",
                phastCons => "$genome/raw/phastCons",
               );
%out_dirs =
  map { $_ => File::Spec->rel2abs(File::Spec->canonpath($out_dirs{$_})) }
  keys %out_dirs;
map { make_path($out_dirs{$_}) } keys %out_dirs;

# make files
my %out_files = (
                 bed       => "$out_ext.bed.gz",
                 snpfile   => "$out_ext.snp.gz",
                 gene      => 'knownGene.txt.gz',
                 phyloP    => 'phyloP.txt.gz',
                 phastCons => 'phastCons.txt.gz',
                 snp       => 'snp141.txt.gz',
                );
%out_files =
  map { $_ => File::Spec->catfile($out_dirs{$_}, $out_files{$_}) }
  keys %out_files;

# open file handles
my %out_fhs =
  map { $_ => IO::Compress::Gzip->new($out_files{$_}) } keys %out_files;

# print out for debugging
p %out_dirs;
p %out_files;
p %out_fhs;
p $twobit_genome;

my @chrs = map { "chr$_" } (1 .. 22, 'M', 'X', 'Y');
my (%header, %found_chr, %chr_len, %chr_seq);

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

      # save in bed file (real coordinates)
      say {$out_fhs{bed}}
        join("\t", $data{chrom}, $data{txStart}, $data{txEnd}, $data{name});

      # get real sequence from 2bit file
      $chr_seq{$chr} = Get_gz_seq($chr, $data{txStart}, $data{txEnd});

      # reformat to 1-index sequence
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

      # save 1-index sequence
      $found_chr{$data{chrom}} = \%data;
      $chr_len{$chr} = $data{txEnd} - $data{txStart};

      # check length of sequence is correct after processing
      die "expected lengths to match"
        unless length ${ $chr_seq{$chr} } == ($data{txEnd} - $data{txStart});

    }
  }
}
chdir $out_dirs{raw} or die "cannot change dir $out_dirs{raw}\n";
p %found_chr;

# print fake knownGene data
{
  say {$out_fhs{gene}} join("\t", (map { $_ } (sort keys %header)));
  for my $chr (sort keys %found_chr)
  {
    say {$out_fhs{gene}}
      join("\t", (map { $found_chr{$chr}{$_} } (sort keys %header)));
  }
}

# print fake conservation data - aboult half of the bases will have scores
for my $chr (@chrs)
{
  for (my $i = 0 ; $i < $chr_len{$chr} ; $i++)
  {
    say {$out_fhs{phastCons}} join("\t", $chr, eval($i + 1), rand(1))
      if rand(1) > 0.5;
    say {$out_fhs{phyloP}} join("\t", $chr, eval($i + 1), eval(rand(60) - 30))
      if rand(1) > 0.5;
  }
}

# print fake snp data - about 1% of sites will be snps
{
  my @snp_fields = qw( chrom chromStart chromEnd name alleleFreqCount alleles alleleFreqs );
  say { $out_fhs{snp} } join("\t", @snp_fields);
  my @alleles = qw( A C G T );
  my %seen_snp_name;
  for my $chr (@chrs)
  {
    for (my $i = 0 ; $i < $chr_len{$chr} ; $i++)
    {
      if (rand(1) > 0.99)
      {
        #  I strongly suspect that the mysql tables are zero-index
        #  and I know that the ucsc browser is 1 indexed.

        my $ref_base = uc substr( ${ $chr_seq{$chr} }, $i, 1 );
        my $minor_allele;
        my $name = 'rs' . int(rand(1000000));
        my @allele_freq;
        push @allele_freq, sprintf("%0.2f", rand(1));
        push @allele_freq, sprintf("%0.2f", eval(1 - $allele_freq[0]));
        @allele_freq = sort { $b <=> $a } @allele_freq;
        my @allele_freq_counts = map { $_ * 1000 } @allele_freq;

        do {
          $name = 'rs' . int(rand(1000000));
        } while ( exists $seen_snp_name{$name} );
        $seen_snp_name{$name}++;
        do {
          $minor_allele = uc $alleles[ int( rand ( $#alleles ) ) ];
        } while ( $minor_allele eq $ref_base );

        say { $out_fhs{snp} } join("\t",
          $chr,
          $i,           # start
          eval($i + 1), # end
          $name,
          join(",", @allele_freq_counts),
          join(",", $ref_base, $minor_allele),
          join(",", @allele_freq));
        # choose site (with 'known' snp) for snpfile
        $snpfile_sites{"$chr:$i"} = join(":", $ref_base, $minor_allele) if (rand(1) > 0.50);
      } # choose site for snpfile
      elsif (rand(1) > 0.995) {
        my $ref_base = uc substr( ${ $chr_seq{$chr} }, $i, 1 );
        my $minor_allele;
        do {
          $minor_allele = uc $alleles[ int(rand(3))  ];
        } while ( $minor_allele eq $ref_base );
        $snpfile_sites{"$chr:$i"} = join(":", $ref_base, $minor_allele);
      }
    }
  }
}

Print_snpfile( $out_fhs{snpfile}, \%snpfile_sites, '10');

# the following just prints out ids who are homozygous for the minor allele;
# limitations:
#   - if the y chromsome is included having a polymorphic y chr will make them men
#   - every one who is non-referance is a homozygote carrier
sub Print_snpfile {
    my ($fh, $snpfile_href, $ids) = @_;

    my @ids = map { 'id_' . $_ } (0..$ids);
    my @header = qw/ Fragment Position Reference Type Alleles Allele_Counts /;

    # print header
    say {$fh} join("\t", join("\t", @header), join("\t\t", @ids));

    for my $site (sort keys %$snpfile_href) {
        my ($chr, $pos) = split(/:/, $site);
        my ($ref_allele, $minor_allele) = split(/:/, $snpfile_href->{$site});
        my $carriers = 0;
        while ($carriers == 0) {
            $carriers = int( rand( $#ids ) );
        }
        my $minor_allele_counts = 2 * $carriers;

        # print out preamble
        my $prnt_str = join("\t", $chr, $pos, $ref_allele, 'SNP', $minor_allele, $minor_allele_counts) . "\t";

        # determine who should be homozygote carrier
        my @shuffled_ids = shuffle @ids;
        my @carrier_ids  = @shuffled_ids[0..$carriers];
        my @alleles = ( );
        for my $id (@ids) {
            if (grep {/\A$id\Z/} @carrier_ids) {
                push @alleles, join("\t", $minor_allele, '1');
            }
            else {
                push @alleles, join("\t", $ref_allele, '1');
            }
        }

        # print out carrier stuff
        $prnt_str .= join("\t", @alleles);
        say {$fh} $prnt_str;
    }
}

# returns scalar reference to sequence for region
sub Get_gz_seq
{
  my ($chr, $start, $end) = @_;
  die "error processing Get_gz_seq() arguments @_"
    unless $chr
    and $start
    and $end;

  # grab sequence
  my $fa_file = qq{$chr.fa};
  my $cmd     = qq{$twobit2fa_prog $twobit_genome:$chr:$start-$end $fa_file};
  say $cmd if $verbose;
  system $cmd;

  # check we got sequence
  die "error grabbing sequence with cmd:\n\t$cmd\n" unless (-s $fa_file);

  # get length of sequence
  #   and gzip file
  my $seq = '';
  my $fa_fh  = IO::File->new($fa_file, 'r');
  my $gz_fh  = IO::Compress::Gzip->new("$fa_file.gz")
    or die "gzip failed: $GzipError\n";
  while (<$fa_fh>)
  {
    chomp $_;
    $seq .= $_ unless ($_ =~ m/\A>/);
    say { $gz_fh } $_;
  }
  say join(" ", $chr, "=>", length $seq) if $verbose;
  unlink $fa_file;
  return \$seq;
}
