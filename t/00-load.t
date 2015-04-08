#!perl -T
use 5.10.0;
use strict;
use warnings;
use Test::More;

plan tests => 24;

BEGIN {
  use_ok('Seq')                              || print "Bail out!\n";
  use_ok('Seq::Assembly')                    || print "Bail out!\n";
  use_ok('Seq::Role::ConfigFromFile')        || print "Bail out!\n";
  use_ok('Seq::Role::IO')                    || print "Bail out!\n";
  use_ok('Seq::Role::Genome')                || print "Bail out!\n";
  use_ok('Seq::Role::Serialize')             || print "Bail out!\n";
  use_ok('Seq::Config::GenomeSizedTrack')    || print "Bail out!\n";
  use_ok('Seq::Config::SparseTrack')         || print "Bail out!\n";
  use_ok('Seq::BDBManager')                  || print "Bail out!\n";
  use_ok('Seq::Fetch')                       || print "Bail out!\n";
  use_ok('Seq::Fetch::Files')                || print "Bail out!\n";
  use_ok('Seq::Fetch::Sql')                  || print "Bail out!\n";
  use_ok('Seq::Site')                        || print "Bail out!\n";
  use_ok('Seq::Site::Gene')                  || print "Bail out!\n";
  use_ok('Seq::Site::Snp')                   || print "Bail out!\n";
  use_ok('Seq::Site::Annotation')            || print "Bail out!\n";
  use_ok('Seq::Gene')                        || print "Bail out!\n";
  use_ok('Seq::Build::GenomeSizedTrackChar') || print "Bail out!\n";
  use_ok('Seq::Build::GenomeSizedTrackStr')  || print "Bail out!\n";
  use_ok('Seq::Build::SparseTrack')          || print "Bail out!\n";
  use_ok('Seq::Build::GeneTrack')            || print "Bail out!\n";
  use_ok('Seq::Build::SnpTrack')             || print "Bail out!\n";
  use_ok('Seq::Annotate')                    || print "Bail out!\n";
  use_ok('Seq::Build')                       || print "Bail out!\n";
}
diag("Testing Seq, Perl $], $^X");
