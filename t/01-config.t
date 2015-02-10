#!perl -T
use 5.10.0;
use strict;
use warnings;
use Test::More;
use YAML::XS qw(LoadFile);

plan tests => 57;

# let the tests begin
#

# test the package's attributes and type constraints
my $package = "Seq::Config";

# load package
use_ok($package) || die "$package cannot be loaded";

# check package uses Moose
ok( $package->can('meta'), "$package has a meta() method" )
  or BAIL_OUT("$package does not have a meta() method.");

# check type constraints for attributes that should have Str values
for my $attr_name (qw( gene_track_name gene_track_statement genome_name genome_description
  phastCons_dir phyloP_dir seq_dir snp_track_name snp_track_statement))
{
  my $attr = $package->meta->get_attribute($attr_name);
  ok( $attr->has_type_constraint, "Seq::Config $attr_name has a type constraint");
  is( $attr->type_constraint->name, 'Str', "$attr_name type is Str" );
}

# check type constraints for attributes that should have ArrayRef[Str] values
for my $attr_name (qw( chr_names gene_track_annotation_names phastCons_proc_clean_dir 
  phastCons_files phastCons_proc_chr phastCons_proc_init phyloP_proc_clean_dir phyloP_files
  phyloP_proc_chr phyloP_proc_init seq_files seq_proc_init ))
{
  my $attr = $package->meta->get_attribute($attr_name);
  ok( $attr->has_type_constraint, "Seq::Config $attr_name has a type constraint");
  is( $attr->type_constraint->name, 'ArrayRef[Str]', "$attr_name type is ArrayRef[Str]" );
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
my $entry //= $config_href->{$genome} || die "cannot find $genome in $config_file\n";

# make a test object
my $genome_config = Seq::Config->new($entry);

# snp_track_statement - subs in \$fields
my $ok_statement_1 = qq{SELECT chrom, chromStart, chromEnd, name, alleleFreqCount, alleles, alleleFreqs FROM hg38.snp141 where hg38.snp141.chrom = "chr22"};
is( $genome_config->snp_track_statement, $ok_statement_1, "snp_track_statement() substitutes expected values for \$fields" );

# snp_track_statement - doesn't sub in \$fields
my $ok_statement_2 = qq{SELECT chrom, chromStart, chromEnd, name, alleleFreqs FROM hg38.snp141 where hg38.snp141.chrom = "chr22"};
my $new_entry = $entry;
$new_entry->{snp_track_statement} = $ok_statement_2;
$genome_config = Seq::Config->new($new_entry);
is( $genome_config->snp_track_statement, $ok_statement_2,"snp_track_statement() returns expected value" );

#
# check Str data is working - two contexts genome_name() and genome_description()
#
my $expected_name = "hg38";
is( $genome_config->genome_name, $expected_name, "genome_name() gave expected $expected_name");

my $expected_description = "human hg38 chr22 for testing";
is( $genome_config->genome_description, $expected_description, "genome_description() gave expected $expected_description");

#
# check ArrayRefs are working - two contexts chr_names() and gene_track_annotation_names()
#

# check chr_names()
my @chrs      = @{ $genome_config->chr_names };
my @test_chrs = ("chr22");
for (my $i=0; $i<@chrs; $i++)
{
  is( $chrs[$i], $test_chrs[$i], "chr_names() gave expected $test_chrs[$i]" );
}

# check gene_track_annotation_names() 
my @names      = @{ $genome_config->gene_track_annotation_names };
my @test_names = qw( mRNA spID spDisplayID geneSymbol refseq protAcc description rfamAcc );
for (my $i=0; $i<@names; $i++)
{
  is( $names[$i], $test_names[$i], "gene_track_annotation_names() gave expected $test_names[$i]." );
}

