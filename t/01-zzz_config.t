#!perl -T
use 5.10.0;
use strict;
use warnings;
use Test::More;
use YAML::XS qw(LoadFile);

plan tests => 50;

#
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
  ok( $attr->has_type_constraint, "$package $attr_name has a type constraint");
  is( $attr->type_constraint->name, 'Str', "$attr_name type is Str" );
}

# check type constraints for attributes that should have ArrayRef[Str] values
for my $attr_name (qw( chr_names gene_track_annotation_names phastCons_proc_clean_dir
  phastCons_files phastCons_proc_chr phastCons_proc_init phyloP_proc_clean_dir phyloP_files
  phyloP_proc_chr phyloP_proc_init seq_files seq_proc_chr ))
{
  my $attr = $package->meta->get_attribute($attr_name);
  ok( $attr->has_type_constraint, "$package $attr_name has a type constraint");
  is( $attr->type_constraint->name, 'ArrayRef[Str]', "$attr_name type is ArrayRef[Str]" );
}

#
# test data 
#

# hg38 test object
my $hg38_config = Seq::Config->new_with_config( configfile => "./t/hg38.yml" );

# snp_track_statement - subs in $fields
{
  my $ok_statement = qq{SELECT chrom, chromStart, chromEnd, name, alleleFreqCount, alleles, alleleFreqs FROM hg38.snp141};
  is( $hg38_config->snp_track_statement, $ok_statement, "snp_track_statement() substitutes expected values for \$fields" );
}

# check Str data is working - two contexts genome_name() and genome_description()
{
  my $expected_name = "hg38";
  is( $hg38_config->genome_name, $expected_name, "genome_name() gave expected $expected_name");
  my $expected_description = "human";
  is( $hg38_config->genome_description, $expected_description, "genome_description() gave expected $expected_description");
}

{
  # check chr_names()
  my @obs_chrs = @{ $hg38_config->chr_names };
  my @exp_chrs = map { "chr$_" } (1..22, 'M', 'X', 'Y');
  is_deeply( \@obs_chrs, \@exp_chrs, "chr_names() gave expected chrs" );

  # check gene_track_annotation_names()
  my @obs_names = @{ $hg38_config->gene_track_annotation_names };
  my @exp_names = qw( mRNA spID spDisplayID geneSymbol refseq protAcc description rfamAcc );
  is_deeply(\@obs_names, \@exp_names, 'gene_track_annotation_names() works');
}

# dm6 test object
my $dm6_config = Seq::Config->new_with_config( configfile => "./t/dm6.yaml" );

# test snp track is empty
{
  my $ok_statement = '';
  is ( $dm6_config->snp_track_name, $ok_statement, "no snps for dm6");
}

