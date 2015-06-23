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
my $db_name = $ARGV[0];
my $lu      = $ARGV[1];
my $msiz    = 512_000_000;
my $params  = join "#", "msiz=$msiz";
my $db_arg  = join "#", $db_name, $params;

if ( !$db->open( $db_arg, $db->OREADER ) ) {
  printf STDERR ( "open error: %s\n", $db->error );
  exit(1);
}

my $json = Cpanel::JSON::XS->new->utf8->pretty(1);

if ($lu) {
  my $val = $db->get($lu);
  my $href = ( defined $val ) ? decode_json $val : {};
  say join " : ", $lu, $json->encode($href);
  exit;
}

# traverse records
my $cur = $db->cursor;

p $cur;

$cur->jump;

while ( my ( $key, $value ) = $cur->get(1) ) {
  my $href = decode_json $value;
  p $href;

  #  my @prn;
  #  for my $key (keys %$href) {
  #    if (ref $href->{$key} eq "HASH") {
  #      push @prn, join " ", $key, %{ $href->{$key} };
  #    }
  #    else {
  #      push @prn, $key, $href->{$key};
  #    }
  #  }
  #  say join " ", @prn;
}
$cur->disable;

# close the database
if ( !$db->close ) {
  printf STDERR ( "close error: %s\n", $db->error );
}
