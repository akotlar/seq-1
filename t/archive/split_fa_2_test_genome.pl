#!/usr/bin/env perl
# Name:           split_fa_2_test_genome.pl
# Date Created:   Wed Mar 11 10:22:55 2015
# Date Modified:  Wed Mar 11 10:22:55 2015
# By:             TS Wingo
#
# Description:

use 5.10.0;
use strict;
use warnings;
use IO::Compress::Gzip qw( $GzipError );
use IO::Uncompress::Gunzip qw( $GunzipError );
use YAML::XS qw( Dump );

my @chrs    = map { "chr$_" } (1..22, 'M', 'X', 'Y');
my %chr_len = map { $_ => 0 } @chrs;

my $local_file = $ARGV[0];

my $fh = new IO::Uncompress::Gunzip $local_file 
  || die "gunzip failed: $GunzipError\n";
my @genome;
while (<$fh>)
{
  chomp $_;
  next if $_ =~ m/\A>/;
  push @genome, $_; 
}

my $parts = int ( scalar @genome / scalar @chrs );
say $parts;

for (my $i = 0; $i < @chrs; $i++)
{
  my $file = "test_$chrs[$i].fa.gz";
  my $z_fh = IO::Compress::Gzip->new( $file ) ||
    die "gzip failed: $GzipError\n";
  my $this_file_lines = $parts;
  say { $z_fh } ">fake $chrs[$i]";
  while ($this_file_lines and @genome)
  {
    my $line = shift @genome;
    say { $z_fh } $line;
    $chr_len{ $chrs[$i] } += length $line;
    $this_file_lines--;
  }
}

print Dump (%chr_len);
   
