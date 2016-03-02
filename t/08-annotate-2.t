#!perl -T
use Test::More;
use DDP;
use strict;
use warnings;
use 5.10.0;

plan tests =>3;
my $var_type = "DENOVO_DEL";

my @match = $var_type =~ /(SNP|MULTIALLELIC|DEL|INS)/s;

is($match[0], "DEL");

is($1, "DEL", 'Special character $1 contains the matches');

$var_type = "DENOVO_MESS";
if ( $var_type =~ /(SNP|MULTIALLELIC|DEL|INS)/s ) {

} else {
  is($1, "DEL", '$1 remains as previous match');
}