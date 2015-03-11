#!/usr/bin/env perl
# Name:           slice_knownGene2test.pl
# Date Created:   Wed Mar 11 10:22:55 2015
# Date Modified:  Wed Mar 11 10:22:55 2015
# By:             TS Wingo
#
# Description:


use Modern::Perl qw(2013);
use Cpanel::JSON::XS;
use Getopt::Long;
use IO::Compress::Gzip qw($GzipError);
use IO::Uncompress::Gunzip qw($GunzipError);
use Scalar::Util qw(looks_like_number);
use YAML qw(Dump Bless);
use DDP;

#
# objects
#
my $json = new Cpanel::JSON::XS;

#
# variables
#
my (%in_fhs, %data);
my ($verbose, $act, $file_name, $out_ext, $json_file, $data_ref);

#
# get options
#
die "Usage: $0 [-v] [-a] -f <file_name> -j <json_file_name> [-o <out_ext>]\n"
  unless GetOptions(
    'v|verbose' => \$verbose,
    'a|act'     => \$act,
    'f|file=s'  => \$file_name,
    'j|json=s'  => \$json_file,
    'o|out=s'   => \$out_ext,
    ) and $file_name
      and $out_ext;
$verbose++ unless $act;


if($file_name =~ m/\.gz$/)
{
  $in_fhs{$file_name} = new IO::Uncompress::Gunzip "$file_name" 
    or die "gzip failed: $GunzipError\n";
}
else
{
  open ($in_fhs{$file_name}, "<", "$file_name");
}

open my $out_bed, '>', "$out_ext.bed";
open my $out_gene, '>', "$out_ext.gene";

my @chrs = map { "chr$_" } (0..22, 'M', 'X', 'Y');

my (%found, %header);
while($_ = $in_fhs{$file_name}->getline())
{
  chomp $_;
  my @fields = split(/\t/, $_);
  if ($. == 1)
  {
    map { $header{$fields[$_]} = $_ } (0..$#fields);
    next;
  }
  my %data = map { $_ => $fields[$header{$_}] } keys %header;
  next unless grep { /$data{chrom}/ } @chrs;
  if ($data{cdsEnd} != $data{cdsStart} && !exists $found{$data{chrom}})
  {
    #
    # save in bed file (real coordinates)
    #
    say $out_bed join("\t", $data{chrom}, $data{txStart}, $data{txEnd}, $data{name});
    my @exon_starts = split(/\,/, $data{exonStarts});
    my @exon_ends   = split(/\,/, $data{exonEnds});
    my (@new_exon_ends, @new_exon_starts);
    my $txStart = $data{txStart} - 1;
    for (my $i = 0; $i < @exon_starts; $i++)
    {
      my $new_start = $exon_starts[$i] - $txStart;
      push @new_exon_starts, $new_start;
      my $new_ends  = $exon_ends[$i]   - $txStart;
      push @new_exon_ends, $new_ends;
    }
    $data{txEnd}     -= $txStart;
    $data{txStart}   -= $txStart;
    $data{cdsStart}  -= $txStart;
    $data{cdsEnd}    -= $txStart;
    $data{exonStarts} = join(",", @new_exon_starts);
    $data{exonEnds}   = join(",", @new_exon_ends);
    $found{$data{chrom}} = \%data;
  }
}
p %found;

say { $out_gene } join("\t", ( map { $_ } (sort keys %header)));

for my $chr (sort keys %found)
{
  say { $out_gene } join("\t", ( map { $found{$chr}{$_} } (sort keys %header)));
}
