#!perl -T
use 5.10.0;
use strict;
use warnings;
use Test::More;
use Cwd;
use YAML::XS qw(Dump LoadFile);
use DBD::Mock;
use Test::Exception;

plan tests => 43;

BEGIN
{
  chdir("./t");
}

# test the package's attributes and type constraints
my $package = "Seq::Build::Fetch";

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
  is( $attr->type_constraint->name, 'Seq::Config',
    "'config' type is Seq::Config" );
}

#
# test the package with the test data
#

# set test yaml config file
my $config_file = "test_annotation.yml";

# load the config file
my $config_href = LoadFile($config_file)
  || die "cannot load $config_file: $!\n";

# choose a genome entry to test
my $genome = "hg38";
my $hg38_config_href //= $config_href->{$genome}
  || die "cannot find $genome in $config_file\n";

# load configuration package
use_ok( 'Seq::Config' ) || die "cannot load Seq::Config\n";

# make configuration obj
my $hg38_config_obj = Seq::Config->new($hg38_config_href);

# test normal connection and methods
{
  # setup mock DBI driver
  my $drh = DBI->install_driver( 'Mock' );
  my $init_hg38 = Seq::Build::Fetch->new( {
    dsn => 'dbi:Mock',
    config => $hg38_config_obj,
    }
  );

  # check dbh method returns DBI::db obj
  can_ok( $init_hg38, 'dbh' );
  isa_ok( $init_hg38->dbh(), 'DBI::db');

  # test config handles
  is( $init_hg38->genome_name, "hg38", "handles genome_name() works.");
  is( $init_hg38->gene_track_name, "knownGene",
    "handles gene_track_name() works.");
  is( $init_hg38->snp_track_name, "snp141", "handles snp_track_name() works.");
  my $exp_statement = qq{SELECT * FROM hg38.knownGene LEFT JOIN hg38.kgXref ON hg38.kgXref.kgID = hg38.knownGene.name};
  is( $init_hg38->gene_track_statement, $exp_statement,
    "handles gene_track_statement() works.");
  $exp_statement = q{SELECT $fields FROM hg38.snp141 where hg38.snp141.chrom = "chr22"};
  like( $init_hg38->snp_track_statement, qr/snp141/,
    "handles snp_track_statement() works.");

  # test good connection succeedes
  lives_ok { $init_hg38->dbh } 'dbh() succeeds if connection works.';
  lives_ok { $init_hg38->get_sql_aref('snp') } 'get_sql_aref() succeeds if connection works.';
}

# test failure to connect throws error
{
  my $drh = DBI->install_driver( 'Mock' );
  $drh->{mock_connect_fail} = 1;
  my $init_hg38 = Seq::Build::Fetch->new( {
    dsn => 'dbi:Mock',
    config => $hg38_config_obj,
    }
  );
  throws_ok { $init_hg38->dbh } qr/Could not connect/,
    'dbh() fails if Db connection fails.';
  throws_ok { $init_hg38->get_sql_aref('snp') } qr/Could not connect/,
    'get_sql_aref() fails if Db connection fails.';
}

# test loss of Db connection throws error
TODO: {
  local $TODO = 'do not understand why these continue to fail (i.e., succeed)';
  my $drh = DBI->install_driver( 'Mock' );
  $drh->{mock_connect_fail} = 0;
  my $init_hg38 = Seq::Build::Fetch->new( { dsn => 'dbi:Mock', config => $hg38_config_obj, });
  my $sth = eval{  $init_hg38->dbh()->prepare('Select foo FROM bar') };
  $init_hg38->dbh()->{mock_can_connect} = 0;
  throws_ok { $sth->execute(); } qr/Could not connect/, 'basic dbh error thrown';
  throws_ok { $init_hg38->get_sql_aref('snp') } qr/Could not connect/,
    'get_sql_aref() fails if Db connection fails';
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
  my $init_hg38 = Seq::Build::Fetch->new( {
    dsn => 'dbi:SQLite:dbname=test',
    host => '',
    user => '',
    config => $local_hg38_config_obj,
    }
  );
  my $exp_data = [ [ 1, 'GRN', 55 ], [ 2, 'Titan', 222, ], ];
  my $obs_data = $init_hg38->get_sql_aref('snp');
  is_deeply( $obs_data, $exp_data, 'fetched sql data');
}

# write fetched sql data
{
  my $drh = DBI->install_driver( 'SQLite' );
  my $local_hg38_config_href = $hg38_config_href;
  $local_hg38_config_href->{snp_track_statement} = 'SELECT id, name, feature FROM test';
  my $local_hg38_config_obj = Seq::Config->new($local_hg38_config_href);
  my $init_hg38 = Seq::Build::Fetch->new( {
    dsn => 'dbi:SQLite:dbname=test',
    host => '',
    user => '',
    config => $local_hg38_config_obj,
    }
  );
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
  is_deeply( \@obs_data, $exp_data, 'wrote sql data');
}

# check we say scripts to download data
for my $type (qw(seq phastCons phyloP))
{
  # setup expected data
  my $dir       = $hg38_config_href->{"$type\_dir"};
  my $file_aref = $hg38_config_href->{"$type\_files"};
  my $command = "rsync -naz rsync://$dir";
  my $exp_script = join("\n", "#!/bin/bash",
    map { "$command/$_ ." } @$file_aref);
  my $local_hg38_config_obj = Seq::Config->new($hg38_config_href);
  my $init_hg38 = Seq::Build::Fetch->new( {
    config => $local_hg38_config_obj,
    }
  );
  my $obs_script = $init_hg38->say_fetch_files_script( $type );
  is ($obs_script, $exp_script, "write script for $type data");
}

# check we say scripts correctly for processing downloaded data
for my $type (qw(seq phastCons phyloP))
{
  # choose dm6 b/c it needs scripts to process genome
  my $dm6_config_href //= $config_href->{dm6};

  # move the following to the init script itself (i.e., not the method)
  my $cwd = cwd();
  my $create_cons_prog  = "python $cwd/create_cons.py";
  my $split_wigFix_prog = "python $cwd/split_wigFix.py";
  my $extract_prog      = "python $cwd/extract.py";
  #$exp_script =~ s/create_cons\.py/$create_cons_prog/g;
  #$exp_script =~ s/extract\.py/$extract_prog/g;
  #$exp_script =~ s/split_wigFix\.py/$split_wigFix_prog/g
  #sub time_stamp {
  #return sprintf("%d-%02d-%02d", eval(localtime->year() + 1900),
  #  eval(localtime->mon() + 1), localtime->mday());
  #};

  # setup expected data
  my @cmds;
  foreach my $step ( qw(proc_init proc_chr proc_dir_clean) )
  {
    my $key = "$type\_$step";
    next unless exists $dm6_config_href->{$key};
    if ($step eq "proc_chr")
    {
      foreach my $chr (@{$dm6_config_href->{chr_names}})
      {
        my $this_cmd = join("\n", @{$dm6_config_href->{$key}});
        $this_cmd =~ s/\$dir/$type/g;
        $this_cmd =~ s/\$chr/$chr/g;
        push @cmds, $this_cmd;
      }
    }
    else
    {
      my $this_cmd = join("\n", @{$dm6_config_href->{$key}});
      push @cmds, $this_cmd;
    }
  }
  my $exp_script = (@cmds) ? join("\n", "#!/bin/bash", @cmds) : undef;
  my $local_dm6_config_obj = Seq::Config->new($dm6_config_href);
  my $init_dm6 = Seq::Build::Fetch->new( { config => $local_dm6_config_obj, });
  my $obs_script = $init_dm6->say_process_files_script( $type );
  is( $obs_script, $exp_script, "say $type processing script" );
}

# check rsync options are set correctly
{
  my %rsync_opts;
  $rsync_opts{1}{1} = "-avzP";
  $rsync_opts{1}{0} = "-az";
  $rsync_opts{0}{1} = "-navzP";
  $rsync_opts{0}{0} = "-naz";
  my $local_hg38_config_obj = Seq::Config->new($hg38_config_href);
  my (@obs_rsync, @exp_rsync);
  foreach my $act (sort keys %rsync_opts)
  {
    foreach my $verbose (sort keys %{ $rsync_opts{$act} })
    {
      my $init_hg38 = Seq::Build::Fetch->new( {
        act => $act,
        verbose => $verbose,
        config => $local_hg38_config_obj,
        }
      );
      push @obs_rsync, $init_hg38->_get_rsync_opts();
      push @exp_rsync, $rsync_opts{$act}{$verbose};
    }
  }
  is_deeply(\@obs_rsync, \@exp_rsync, , 'ok _get_rsync_opts');
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