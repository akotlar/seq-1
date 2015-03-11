#!perl -T
use 5.10.0;
use strict;
use warnings;
use Test::More;

plan tests => 15; 

BEGIN {
    use_ok( 'Seq' ) || print "Bail out!\n";
    use_ok( 'Seq::ConfigFromFile' ) || print "Bail out!\n";
    use_ok( 'Seq::Config::GenomeSizedTrack' ) || print "Bail out!\n";
    use_ok( 'Seq::Config::SparseTrack' ) || print "Bail out!\n";
    use_ok( 'Seq::Fetch' ) || print "Bail out!\n";
    use_ok( 'Seq::Fetch::Files' ) || print "Bail out!\n";
    use_ok( 'Seq::Fetch::Sql' ) || print "Bail out!\n";
    use_ok( 'Seq::Gene' ) || print "Bail out!\n";
    use_ok( 'Seq::GeneSite' ) || print "Bail out!\n";
    use_ok( 'Seq::SnpSite' ) || print "Bail out!\n";
    use_ok( 'Seq::Build::GenomeSizedTrackChar' ) || print "Bail out!\n";
    use_ok( 'Seq::Build::GenomeSizedTrackStr' ) || print "Bail out!\n";
    use_ok( 'Seq::Build' ) || print "Bail out!\n";
}
diag( "Testing Seq $Seq::VERSION, Perl $], $^X" );
