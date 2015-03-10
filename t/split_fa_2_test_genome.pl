#!/usr/bin/env perl
use 5.10.0;
use strict;
use warnings;
use IO::Compress::Gzip qw( $GzipError );
use IO::Uncompress::Gunzip qw( $GunzipError );

my @chrs = map { "chr$_" } (1..22, 'M', 'X', 'Y');

my $local_file = $ARGV[0];

my $fh = new IO::Uncompress::Gunzip $local_file || die "gunzip failed: $GunzipError\n";
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
    $this_file_lines--;
  }
}
   
