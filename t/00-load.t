#!perl -T
use 5.10.0;
use strict;
use warnings;
use Test::More;

plan tests => 9;

BEGIN {
    use_ok( 'Seq' ) || print "Bail out!\n";
    use_ok( 'Seq::Annotate' ) || print "Bail out!\n";
    use_ok( 'Seq::Build::Fetch') || print "Bail out!\n";
    use_ok( 'Seq::Build::GenomeSizedTrack') || print "Bail out!\n";
    use_ok( 'Seq::Build::SparseTrack') || print "Bail out!\n";
    use_ok( 'Seq::Config' ) || print "Bail out!\n";
    use_ok( 'Seq::Gene' ) || print "Bail out!\n";
    use_ok( 'Seq::Genome') || print "Bail out!\n";
    use_ok( 'Seq::Serialize' ) || print "Bail out!\n";
}

diag( "Testing Seq $Seq::VERSION, Perl $], $^X" );
