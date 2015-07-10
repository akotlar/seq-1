#!perl -T
use 5.10.0;
use strict;
use warnings;

use Lingua::EN::Inflect qw( A PL_N );
use Path::Tiny;
use Scalar::Util qw( blessed );
use Test::More;
use YAML qw/ LoadFile /;

use DDP;

plan tests => 40;

# set test genome
my $ga_config  = path('./config/hg38.yml')->absolute->stringify;
my $config_href = LoadFile( $ga_config );

my $package = "Seq::Config::SparseTrack";

# load package
use_ok($package) || die "$package cannot be loaded";

# check is moose object
check_isa( $package, ['Seq::Config::Track','Moose::Object']);

# Attribute tests
my @ro_attrs = qw/ type sql_statement features /;
for my $attr ( @ro_attrs ) {
  has_ro_attr( $package, $attr );
}
# check type constraints - SparseTrackType
for my $attr_name (qw/ type /) {
  my $attr = $package->meta->get_attribute($attr_name);
  ok( $attr->has_type_constraint, "$package $attr_name has a type constraint" );
  is( $attr->type_constraint->name,
    'SparseTrackType', "$attr_name type is SparseTrackType" );
}

{
  # object creation
  my $href = build_obj_data( 'sparse_tracks', 'snp', $config_href );
  my @features = qw/ alleleFreqCount alleles alleleFreqs /;
  $href->{features} = \@features;
  my $obj = $package->new( $href );
  ok($obj, 'object creation');

  # local files
  my $exp_path = path($config_href->{genome_raw_dir})->child('./snp/hg38.snp141.txt')->absolute;
  is_deeply( $obj->all_local_files, $exp_path, 'local_files');

  $exp_path = path($config_href->{genome_index_dir})->child('snp141.snp.chr1.kch')->absolute;
  is( $obj->get_kch_file( 'chr1' ), $exp_path, 'method: get_kch_file');

  $exp_path = path($config_href->{genome_index_dir})->child('snp141.snp.chr1.dat')->absolute;
  is ($obj->get_dat_file( 'chr1' ), $exp_path, 'method: get_dat_file');

  # check snp sparse track

  my $st       = $package->new(
    {
      name          => 'snp141',
      type          => 'snp',
      sql_statement => 'SELECT _snp_fields FROM hg38.snp141',
      features      => \@features,
      local_file    => ['snp141.txt.gz'],
      genome_chrs   => $config_href->{genome_chrs},
    }
  );

  my $sql_stmt =
    q{SELECT chrom, chromStart, chromEnd, name, alleleFreqCount, alleles, alleleFreqs FROM hg38.snp141};
  is( $sql_stmt, $st->sql_statement, '(snp_track) method: Sql statement' );

  my @all_snp_fields = qw/ chrom chromStart chromEnd name /;
  push @all_snp_fields, @features;

  is_deeply( \@all_snp_fields, $st->snp_fields_aref, '(snp_track) method: Snp Fields Aref' );

  is( undef, $st->gene_fields_aref, '(snp_track) method: Gene Fields Aref' );

  my @got_features = $st->all_features;
  is_deeply( \@features, \@got_features, '(snp_track) method: features' );
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
      genome_chrs   => $config_href->{genome_chrs},
    }
  );

  my $sql_stmt =
    q{SELECT chrom, strand, txStart, txEnd, cdsStart, cdsEnd, exonCount, exonStarts, exonEnds, name, mRNA, spID, spDisplayID, geneSymbol, refseq, protAcc, description, rfamAcc FROM hg38.knownGene LEFT JOIN hg38.kgXref ON hg38.kgXref.kgID = hg38.knownGene.name};

  is( $sql_stmt, $st->sql_statement, '(gene_track) method: Sql statement' );

  my @all_gene_fields =
    qw/ chrom strand txStart txEnd cdsStart cdsEnd exonCount exonStarts exonEnds name /;

  push @all_gene_fields, @features;

  is_deeply( \@all_gene_fields, $st->gene_fields_aref, '(gene_track) method: Gene Fields Aref' );

  is( undef, $st->snp_fields_aref, '(gene_track) method: Snp Fields Aref' );

  my @got_features = $st->all_features;

  is_deeply( \@features, \@got_features, '(gene_track) method: features' );
}

sub build_obj_data {
  my ( $track_type, $type, $href ) = @_;

  my %hash;

  # get essential stuff
  for my $track ( @{ $config_href->{$track_type} } ) {
    if ( $track->{type} eq $type) {
      for my $attr (qw/ name type local_files remote_dir remote_files /) {
        $hash{$attr} = $track->{$attr} if exists $track->{$attr};
      }
    }
  }

  # add additional stuff
  if ( %hash ) {
    $hash{genome_raw_dir} = $config_href->{genome_raw_dir}  || 'sandbox';
    $hash{genome_index_dir} = $config_href->{genome_index_dir} || 'sandbox';
    $hash{genome_chrs} = $config_href->{genome_chrs};
  }
  return \%hash;
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
