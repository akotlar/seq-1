#!/usr/bin/env perl
# Name:           fake_conserv_score.pl
# Date Created:   Sun Mar 15 23:04:55 2015
# Date Modified:  Sun Mar 15 23:04:55 2015
# By:             TS Wingo
#
# Description:

use Getopt::Long;
use IO::Compress::Gzip qw($GzipError);
use IO::File;

#
# variables
#
my ( %in_fhs, %data );
my ( $verbose, $act, $genome_length );

#
# get options
#
die "Usage: $0 [-v] [-a]\n"
  unless GetOptions(
    'v|verbose' => \$verbose,
    'a|act'     => \$act,
    'l|len=n'   => \$genome_length,
  );
$verbose++ unless $act;

my @chrs = map { "chr" . $_ } ( 1 .. 22, 'M', 'X', 'Y' );
my $chr_len = int( $genome_length / scalar @chrs );

# imagine one is -1 to 1 and the other 0-2.5

my $out_phastCons = IO::Compress::Gzip->new('phastCons.txt.gz')
  or die "$GzipError opening phastConst.txt.gz: $!\n";

my $out_phyloP = IO::Compress::Gzip->new('phyloP.txt.gz')
  or die "$GzipError opening phyloPt.txt.gz: $!\n";

for my $chr (@chrs) {
    for ( my $i = 0; $i < $chr_len; $i++ ) {
        say $out_phastCons join( "\t", $chr, eval( $i + 1 ), rand(1) );
        say $out_phyloP join( "\t", $chr, eval( $i + 1 ), eval( rand(60) - 30 ) );
    }
}

