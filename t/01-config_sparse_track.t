#!perl -T
use 5.10.0;
use strict;
use warnings;

use DDP;
use File::Copy;
use Lingua::EN::Inflect qw/ A PL_N /;
use Path::Tiny;
use Scalar::Util qw/ blessed /;
use Test::More;

plan tests => 40;

# set test genome
my $hg38_node03_config = path('./config/hg38_node03.yml')->absolute->stringify;
my $hg38_local_config  = path('./config/hg38_local.yml')->absolute->stringify;

# setup testing enviroment
{
  make_path('./sandbox') unless -d './sandbox';
  chdir("./sandbox");
}

my $package = "Seq::Config::SparseTrack";

# load package
use_ok($package) || die "$package cannot be loaded";

# check is moose object
check_isa( $package, ['Moose::Object'] );

# check package uses Moose
ok( $package->can('meta'), "$package has a meta() method" )
  or BAIL_OUT("$package does not have a meta() method.");

# check read-only attribute have read but no write methods
has_ro_attr( $package, $_ )
  for (
  qw/ local_dir local_file
  name type features sql_statement /
  );

# check type constraints - Str
for my $attr_name ( qw/ local_dir local_file name sql_statement / )
{
  my $attr = $package->meta->get_attribute($attr_name);
  ok( $attr->has_type_constraint, "$package $attr_name has a type constraint" );
  is( $attr->type_constraint->name, 'Str', "$attr_name type is Str" );
}

# check type constraints - SparseTrackType
for my $attr_name (qw/ type /) {
  my $attr = $package->meta->get_attribute($attr_name);
  ok( $attr->has_type_constraint, "$package $attr_name has a type constraint" );
  is( $attr->type_constraint->name,
    'SparseTrackType', "$attr_name type is SparseTrackType" );
}

{
  # check snp sparse track
  my @features = qw/ alleleFreqCount alleles alleleFreqs /;
  my $st       = $package->new(
    {
      name          => 'snp141',
      type          => 'snp',
      sql_statement => 'SELECT _snp_fields FROM hg38.snp141',
      features      => \@features,
      local_dir     => './hg38/raw/snp',
      local_file    => 'snp141.txt.gz',
    }
  );

  my $sql_stmt =
    q{SELECT chrom, chromStart, chromEnd, name, alleleFreqCount, alleles, alleleFreqs FROM hg38.snp141};
  is( $sql_stmt, $st->sql_statement, 'Sql statement' );

  my @all_snp_fields = qw/ chrom chromStart chromEnd name /;
  push @all_snp_fields, @features;

  is_deeply( \@all_snp_fields, $st->snp_fields_aref, 'Got Snp Fields Aref' );

  is( undef, $st->gene_fields_aref, 'Got Gene Fields Aref' );

  my @got_features = $st->all_features;
  is_deeply( \@features, \@got_features, 'got features' );
}

{
  # check gene sparse track
  my @features =
    qw/ mRNA spID spDisplayID geneSymbol refseq protAcc description rfamAcc /;
  my $st = $package->new(
    {
      name => 'knownGene',
      type => 'gene',
      sql_statement =>
        'SELECT _gene_fields FROM hg38.knownGene LEFT JOIN hg38.kgXref ON hg38.kgXref.kgID = hg38.knownGene.name',
      features   => \@features,
      local_dir  => './hg38/raw/gene',
      local_file => 'knownGene.txt.gz',
    }
  );
  my $sql_stmt =
    q{SELECT chrom, strand, txStart, txEnd, cdsStart, cdsEnd, exonCount, exonStarts, exonEnds, name, mRNA, spID, spDisplayID, geneSymbol, refseq, protAcc, description, rfamAcc FROM hg38.knownGene LEFT JOIN hg38.kgXref ON hg38.kgXref.kgID = hg38.knownGene.name};
  is( $sql_stmt, $st->sql_statement, 'Sql statement' );

  my @all_gene_fields = qw/ chrom strand txStart txEnd cdsStart cdsEnd exonCount exonStarts exonEnds name /;
  push @all_gene_fields, @features;

  is_deeply( \@all_gene_fields, $st->gene_fields_aref, 'Got Gene Fields Aref' );

  is( undef, $st->snp_fields_aref, 'Got Snp Fields Aref' );

  my @got_features = $st->all_features;
  is_deeply( \@features, \@got_features, 'got features' );
}

sub check_isa {
  my $class   = shift;
  my $parents = shift;

  local $Test::Builder::Level = $Test::Builder::Level + 1;

  my @isa = $class->meta->linearized_isa;
  shift @isa; # returns $class as the first entry

  my $count = scalar @{$parents};
  my $noun = PL_N( 'parent', $count );

  is( scalar @isa, $count, "$class has $count $noun" );

  for ( my $i = 0; $i < @{$parents}; $i++ ) {
    is( $isa[$i], $parents->[$i], "parent[$i] is $parents->[$i]" );
  }
}

sub has_ro_attr {
  my $class = shift;
  my $name  = shift;

  local $Test::Builder::Level = $Test::Builder::Level + 1;

  my $articled = A($name);
  ok( $class->meta->has_attribute($name), "$class has $articled attribute" );

  my $attr = $class->meta->get_attribute($name);

  is( $attr->get_read_method, $name,
    "$name attribute has a reader accessor - $name()" );
  is( $attr->get_write_method, undef, "$name attribute does not have a writer" );
}

sub has_rw_attr {
  my $class      = shift;
  my $name       = shift;
  my $overridden = shift;

  local $Test::Builder::Level = $Test::Builder::Level + 1;

  my $articled = $overridden ? "an overridden $name" : A($name);
  ok( $class->meta->has_attribute($name), "$class has $articled attribute" );

  my $attr = $class->meta->get_attribute($name);

  is( $attr->get_read_method, $name,
    "$name attribute has a reader accessor - $name()" );
  is( $attr->get_write_method, $name,
    "$name attribute has a writer accessor - $name()" );
}
