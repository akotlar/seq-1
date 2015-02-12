#!perl -T
use 5.10.0;
use strict;
use warnings;
use Test::More;
use YAML::XS qw(Dump LoadFile);
use DBD::Mock;
use Test::Exception;

plan tests => 36;

# test the package's attributes and type constraints
my $package = "Seq::Config::Init";

# load package
use_ok($package) || die "$package cannot be loaded";

# check package uses Moose
ok( $package->can('meta'), "$package has a meta() method" )
  or BAIL_OUT("$package does not have a meta() method.");

# check type constraints for attributes that should have Str values
for my $attr_name (qw( dsn host user password socket  ))
{
  my $attr = $package->meta->get_attribute($attr_name);
  ok( $attr->has_type_constraint, "$package $attr_name has a type constraint");
  is( $attr->type_constraint->name, 'Str', "$attr_name type is Str" );
}

# check type constraints for attributes that should have Int values
for my $attr_name (qw( port act verbose ))
{
  my $attr = $package->meta->get_attribute($attr_name);
  ok( $attr->has_type_constraint, "$package $attr_name has a type constraint");
  is( $attr->type_constraint->name, 'Int', "$attr_name type is Int" );
}

# check type constraints for attributes that should have Seq::Config values
{
  my $attr = $package->meta->get_attribute('config');
  ok( $attr->has_type_constraint, "$package 'config' has a type constraint");
  is( $attr->type_constraint->name, 'Seq::Config', "'config' type is Seq::Config" );
}

#
# test the package with the test data
#

# set test yaml config file
my $config_file = "./t/test_annotation.yml";

# load the config file
my $config_href = LoadFile($config_file) || die "cannot load $config_file: $!\n";

# choose a genome entry to test
my $genome = "hg38";
my $hg38_config_href //= $config_href->{$genome} || die "cannot find $genome in $config_file\n";

# load configuration package
use_ok( 'Seq::Config' ) || die "cannot load Seq::Config\n";

# make configuration obj
my $hg38_config_obj = Seq::Config->new($hg38_config_href);

# test normal connection and methods
{
  # setup mock DBI driver
  my $drh = DBI->install_driver( 'Mock' );
  my $init_hg38 = Seq::Config::Init->new( { dsn => 'dbi:Mock', config => $hg38_config_obj, });

  # check dbh method returns DBI::db obj
  can_ok( $init_hg38, 'dbh' );
  isa_ok( $init_hg38->dbh(), 'DBI::db');

  # test config handles
  is( $init_hg38->genome_name, "hg38", "handles genome_name() works.");
  is( $init_hg38->gene_track_name, "knownGene", "handles gene_track_name() works.");
  is( $init_hg38->snp_track_name, "snp141", "handles snp_track_name() works.");
  my $exp_statement = qq{SELECT * FROM hg38.knownGene LEFT JOIN hg38.kgXref ON hg38.kgXref.kgID = hg38.knownGene.name where hg38.knownGene.chrom = "chr22"};
  is( $init_hg38->gene_track_statement, $exp_statement, "handles gene_track_statement() works.");
  $exp_statement = q{SELECT $fields FROM hg38.snp141 where hg38.snp141.chrom = "chr22"};
  like( $init_hg38->snp_track_statement, qr/snp141/, "handles snp_track_statement() works.");

  # test good connection succeedes
  lives_ok { $init_hg38->dbh } 'dbh() succeeds if connection works.';
  lives_ok { $init_hg38->get_sql_data('snp') } 'get_sql_data() succeeds if connection works.';
}

# test failure to connect throws error
{
  my $drh = DBI->install_driver( 'Mock' );
  $drh->{mock_connect_fail} = 1;
  my $init_hg38 = Seq::Config::Init->new( { dsn => 'dbi:Mock', config => $hg38_config_obj, });
  throws_ok { $init_hg38->dbh } qr/Could not connect/, 'dbh() fails if Db connection fails.';
  throws_ok { $init_hg38->get_sql_data('snp') } qr/Could not connect/, 'get_sql_data() fails if Db connection fails.';
}

# test loss of Db connection throws error
TODO: {
  local $TODO = 'do not understand why these continue to fail (i.e., succeed)';
  my $drh = DBI->install_driver( 'Mock' );
  $drh->{mock_connect_fail} = 0;
  my $init_hg38 = Seq::Config::Init->new( { dsn => 'dbi:Mock', config => $hg38_config_obj, });
  my $sth = eval{  $init_hg38->dbh()->prepare('Select foo FROM bar') };
  $init_hg38->dbh()->{mock_can_connect} = 0;
  throws_ok { $sth->execute(); } qr/Could not connect/, 'basic dbh error thrown';
  throws_ok { $init_hg38->get_sql_data('snp') } qr/Could not connect/, 'get_sql_data() fails if Db connection fails';
}

# setup data for reading sql db tests
#   reads data after __END__
{
  my $dbh = DBI->connect('dbi:SQLite:dbname=test:hg38');
  local $/=";\n";
  $dbh->do( $_ ) while <DATA>;
}

# fetch sql data
{
  my $drh = DBI->install_driver( 'SQLite' );
  # make a local copy of the configuration hashref
  # change SQL statement to something simple to test
  my $local_hg38_config_href = $hg38_config_href;
  $local_hg38_config_href->{snp_track_statement} = 'SELECT id, name, feature FROM test';
  my $local_hg38_config_obj = Seq::Config->new($local_hg38_config_href);
  my $init_hg38 = Seq::Config::Init->new( { dsn => 'dbi:SQLite:dbname=test', host => '', user => '', config => $local_hg38_config_obj, });
  my $exp_data = [ [ 1, 'GRN', 55 ], [ 2, 'Titan', 222, ], ];
  my @obs_data = $init_hg38->get_sql_data('snp');
  is_deeply( \@obs_data, $exp_data);
}

# write fetched sql data
{
  my $drh = DBI->install_driver( 'SQLite' );
  my $local_hg38_config_href = $hg38_config_href;
  $local_hg38_config_href->{snp_track_statement} = 'SELECT id, name, feature FROM test';
  my $local_hg38_config_obj = Seq::Config->new($local_hg38_config_href);
  my $init_hg38 = Seq::Config::Init->new( { dsn => 'dbi:SQLite:dbname=test', host => '', user => '', config => $local_hg38_config_obj, });
  my $exp_data = [ [ 1, 'GRN', 55 ], [ 2, 'Titan', 222, ], ];
  open my $out_fh, ">", "test.txt";
  $init_hg38->write_sql_data('snp', $out_fh);
  close $out_fh;
  my @obs_data; 
  open my $in_fh, "<", "test.txt";
  while(<$in_fh>)
  {
    chomp $_;
    my @data = split("\t", $_);
    push @obs_data, \@data;
  }
  is_deeply( \@obs_data, $exp_data);
}


__END__
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
