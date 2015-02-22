#!perl -T
use 5.10.0;
use strict;
use warnings;
use Test::More;

plan tests => 10;

BEGIN {
    use_ok( 'Seq' ) || print "Bail out!\n";
    use_ok( 'Seq::Config::GenomeSizedTrack' ) || print "Bail out!\n";
    use_ok( 'Seq::Config::AnnotationTrack' ) || print "Bail out!\n";
    use_ok( 'Seq::Fetch' ) || print "Bail out!\n";
    use_ok( 'Seq::Fetch::Files' ) || print "Bail out!\n";
    use_ok( 'Seq::Fetch::Sql' ) || print "Bail out!\n";
}

diag( "Testing Seq $Seq::VERSION, Perl $], $^X" );
