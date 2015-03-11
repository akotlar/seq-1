#!/usr/bin/env perl
# Name:           proc_fasta_2_chr.pl
# Date Created:   Wed Mar 11 12:32:34 2015
# Date Modified:  Wed Mar 11 12:32:34 2015
# By:             TS Wingo
#
# Description:

use Modern::Perl qw(2013);
use Getopt::Long;
use IO::Compress::Gzip qw($GzipError);
use IO::Uncompress::Gunzip qw($GunzipError);
use YAML qw(Dump Bless);

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
    ) and $file_name;
$verbose++ unless $act;

my @chrs = map { "chr$_" } (1..22, 'M', 'X', 'Y');

if($file_name =~ m/\.gz$/)
{
  $in_fhs{$file_name} = new IO::Uncompress::Gunzip "$file_name" or die "gzip failed: $GunzipError\n";
}
else
{
  open ($in_fhs{$file_name}, "<", "$file_name");
}

my %out_fhs;
for my $chr (@chrs)
{
  $out_fhs{$chr} = IO::Compress::Gzip->new("test_$chr.txt.gz")
    or die "gzip failed: $GzipError";
}

#
# read file
#
my $chr;
while($_ = $in_fhs{$file_name}->getline())
{
  chomp $_;
  if ($_ =~ m/\A>/)
  {
    if ($_ =~ m/range=(chr[\w|\d]*):/)
    {
      die "cannot find file for $1" unless exists $out_fhs{$1};
      $chr = $1;
    }
  }
  say { $out_fhs{$chr} } $_ if $chr;
}

