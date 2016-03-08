use 5.10.0;
use strict;
use warnings;

use Test::More;
use Seq::Annotate;
use DDP;

plan tests => 2;

my $annotator = Seq::Annotate->new_with_config(
  {
    configfile => './config/hg38_test.yml',
    debug      => 1,
  }
);
my $chr = 'chr6';
my $ref = 'G';
my $alt = 'A';
my $pos = 32553401;

my $chr_len_href = $annotator->chr_len;
my $chrs_aref    = $annotator->genome_chrs;
my %chr_index    = map { $chrs_aref->[$_] => $_ } ( 0 .. $#{$chrs_aref} );

my $chr_index  = $chr_index{$chr};
my $chr_offset = $chr_len_href->{$chr};
my $abs_pos    = $chr_offset + $pos - 1;

# R =. A/G
my $record_href = $annotator->annotate(
  $chr,
  $chr_index,
  '32553401',
  $abs_pos, $ref, 'SNP',
  "$ref, $alt",
  '2,4',
  'Sample1;Sample2',
  'Sample3;Sample4',
  {
    Sample1 => 'R',
    Sample2 => 'R',
    Sample3 => 'A',
    Sample4 => 'A'
  }
);

ok( $record_href->{genomic_type} eq 'Intronic' );

p $record_href;

$chr = 'chr3';
$ref = 'C';
$alt = 'G';
$pos = 45989578;

$chr_len_href = $annotator->chr_len;
$chrs_aref    = $annotator->genome_chrs;
%chr_index    = map { $chrs_aref->[$_] => $_ } ( 0 .. $#{$chrs_aref} );

$chr_index  = $chr_index{$chr};
$chr_offset = $chr_len_href->{$chr};
$abs_pos    = $chr_offset + $pos - 1;

# R =. A/G
$record_href = $annotator->annotate(
  $chr,
  $chr_index,
  '32553401',
  $abs_pos, $ref, 'SNP',
  "$ref, $alt",
  '2,4',
  'Sample1;Sample2',
  'Sample3;Sample4',
  {
    Sample1 => 'S',
    Sample2 => 'S',
    Sample3 => 'G',
    Sample4 => 'G'
  }
);

ok( $record_href->{genomic_type} eq 'Intronic' );

p $record_href;
