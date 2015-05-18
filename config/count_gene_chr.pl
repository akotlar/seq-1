#!/usr/bin/env perl
# Name:           count_gene_chr.pl
# Date Created:   Sun May 17 08:59:43 2015
# Date Modified:  Sun May 17 08:59:43 2015
# By:             TS Wingo
#
# Description:


use Modern::Perl qw/ 2013 /;
use Cpanel::JSON::XS;
use Getopt::Long;
use IO::File;
use IO::Uncompress::Gunzip qw/ $GunzipError /;
use YAML::XS;
use bigint;

use DDP;


# variables
my (%in_fhs, %data);
my ($verbose, $act, $file_name, $out_ext, $json_file, $data_ref);

my %ucsc_table_lu = (
    name       => 'transcript_id',
    chrom      => 'chr',
    cdsEnd     => 'coding_end',
    cdsStart   => 'coding_start',
    exonEnds   => 'exon_ends',
    exonStarts => 'exon_starts',
    strand     => 'strand',
    txEnd      => 'transcript_end',
    txStart    => 'transcript_start',
  );

# get options
die "Usage: $0 [-v] [-a] -f <known_gene file> \n"
  unless GetOptions(
    'v|verbose' => \$verbose,
    'a|act'     => \$act,
    'f|file=s'  => \$file_name,
    'j|json=s'  => \$json_file,
    'o|out=s'   => \$out_ext,
    ) and $file_name;
$verbose++ unless $act;

if($file_name =~ m/\.gz$/)
{
  $in_fhs{$file_name} = new IO::Uncompress::Gunzip "$file_name" or die "gzip failed: $GunzipError\n";
}
else
{
  open ($in_fhs{$file_name}, "<", "$file_name");
}

# read file
my (%header, %sites);
while(my $line = $in_fhs{$file_name}->getline())
{
  chomp $line;
  my @fields = split( /\t/, $line );
    if ( $. == 1 ) {
      map { $header{ $fields[$_] } = $_ } ( 0 .. $#fields );
      next;
    }
    my %data = map { $_ => $fields[ $header{$_} ] } ( keys %header );

    # prepare basic gene data
    my @exon_ends   = split( /\,/, $data{exonEnds} );
    my @exon_starts = split( /\,/, $data{exonStarts} );

    for (my $i = 0; $i < @exon_ends; $i++ ) {
      $sites{ $data{chrom} } += ( $exon_ends[$i] + 6 ) - ( $exon_starts[$i] - 6 );
    }
}


my @chrs = map { $_->[0] }
  sort { $a->[1] <=> $b->[1] }
  map { [ $_, $sites{$_} ] } (keys %sites);

for my $chr ( @chrs ) {
  say join "\t", $chr, $sites{$chr};
}

my @real_chrs = map { "chr" . $_ } ( 1 .. 22, 'M', 'X', 'Y' );

for my $chr ( @real_chrs ) {
  say join "\t", $chr, $sites{$chr};
}

