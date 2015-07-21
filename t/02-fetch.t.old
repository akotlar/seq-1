#!perl -T
use 5.10.0;
use strict;
use warnings;
use DBD::Mock;
use File::Copy;
use Test::Exception;
use Test::More;
use YAML::XS qw( LoadFile Dump );
use DDP;

plan tests => 6;

use_ok('Seq::Fetch')        || print "Bail out!\n";
use_ok('Seq::Fetch::Files') || print "Bail out!\n";
use_ok('Seq::Fetch::Sql')   || print "Bail out!\n";

# pick a test genome
my $config_file = File::Spec->rel2abs("./config/hg38.yml");
chdir("./sandbox");

# setup data for reading sql db tests
#   reads data after __END__
{
  my $dbh = DBI->connect('dbi:SQLite:dbname=test_hg38');
  local $/ = ";\n";
  $dbh->do($_) while <DATA>;
}

# load the yaml file
my $hg38_config_href = LoadFile($config_file)
  || die "cannot load $config_file $!\n";

for my $track ( @{ $hg38_config_href->{sparse_tracks} } ) {
  $track->{dsn}           = 'dbi:SQLite:dbname=test_hg38';
  $track->{host}          = '';
  $track->{user}          = '';
  $track->{sql_statement} = 'SELECT id, name, feature FROM test';
}

for my $track ( @{ $hg38_config_href->{genome_sized_tracks} } ) {
  $track->{act}     = 0;
  $track->{verbose} = 1;
}

my $fetch_hg38 = Seq::Fetch->new($hg38_config_href);

isa_ok( $fetch_hg38, 'Seq::Fetch', 'Seq::Fetch made with a hash reference' );

my $fetch_hg38_2 = Seq::Fetch->new_with_config(
  { configfile => $config_file, act => 1, verbose => 1, } );

isa_ok( $fetch_hg38_2, 'Seq::Fetch', 'Seq::Fetch made with a configfile' );

$fetch_hg38_2->fetch_genome_size_tracks;

__DATA__
BEGIN TRANSACTION;
DROP TABLE test;
CREATE TABLE test (
  id int,
  name varchar(25),
  feature int
);
INSERT INTO "test" VALUES(1, 'GRN', 55);
INSERT INTO "test" VALUES(2, 'Titan', 222);
COMMIT;
