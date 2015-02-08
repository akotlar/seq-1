#!perl -T
use 5.10.0;
use strict;
use warnings;
use Test::More;

plan tests => 6;

BEGIN {
    use_ok( 'Seq' ) || print "Bail out!\n";
    use_ok( 'Seq::Annotate' ) || print "Bail out!\n";
    use_ok( 'Seq::Utils' ) || print "Bail out!\n";
    use_ok( 'Seq::Serialize' ) || print "Bail out!\n";
    use_ok( 'Seq::Store' ) || print "Bail out!\n";
    use_ok( 'Seq::Config' ) || print "Bail out!\n";
}

diag( "Testing Seq $Seq::VERSION, Perl $], $^X" );
