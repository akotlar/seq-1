#!/usr/bin/env perl

use 5.10.0;
use warnings;
use strict;
use KyotoCabinet;
use Cpanel::JSON::XS;
use DDP;

# create the database object
my $db = new KyotoCabinet::DB;

# open the database
my $db_name = join ".", $ARGV[0], 'kch';
my $msiz = 128_000_000;
my $bnum = 10_000_000;

my $params = join "#", "opts=HashDB::TLINEAR", 
  "msiz=$msiz", "bnum=$bnum";

my $db_arg = join "#", $db_name, $params;

say $db_arg;

if (!$db->open($db_arg, $db->OWRITER | $db->OCREATE ) ) {
    printf STDERR ("open error: %s\n", $db->error);
    exit(1);
}

for (my $i = 0; $i < 5_000_000; $i++) {
  my %hash;
  for (my $j = 0; $j < int(rand(10)); $j++) {
    $hash{$j} = int(rand(200));
  }

  $db->set( $i, encode_json( \%hash ) );
}

# close the database
if (!$db->close) {
    printf STDERR ("close error: %s\n", $db->error);
}
