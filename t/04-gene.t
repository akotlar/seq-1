#!perl -T
use 5.10.0;
use strict;
use warnings;
use Test::More;
use File::Copy;
use Scalar::Util qw( blessed );
use Lingua::EN::Inflect qw( A PL_N );
use IO::Uncompress::Gunzip qw( $GunzipError );
use DDP;
use YAML qw( LoadFile );

plan tests => 20;

# set test genome
my $hg38_config_file = "hg38_gene_test.yml";

# setup testing enviroment
{
  copy( "./t/$hg38_config_file", "./sandbox/$hg38_config_file" )
    or die "cannot copy ./t/$hg38_config_file to ./sandbox/$hg38_config_file $!";
  chdir("./sandbox");
}

# test the package's attributes and type constraints
my $package = "Seq::Gene";

# load package
use_ok($package) || die "$package cannot be loaded";

# check package extends Seq::Gene which is a Moose::Object
check_isa( $package, ['Moose::Object'] );

# check package uses Moose
ok( $package->can('meta'), "$package has a meta() method" )
  or BAIL_OUT("$package does not have a meta() method.");

# check type constraints for attributes that should have Str values
for my $attr_name (qw( chr strand transcript_id )) {
  my $attr = $package->meta->get_attribute($attr_name);
  ok( $attr->has_type_constraint, "$package $attr_name has a type constraint" );
  is( $attr->type_constraint->name, 'Str', "$attr_name type is Str" );
}

# check type constraints for attributes that should have Int values
for my $attr_name (qw( transcript_start transcript_end coding_start coding_end )) {
  my $attr = $package->meta->get_attribute($attr_name);
  ok( $attr->has_type_constraint, "$package $attr_name has a type constraint" );
  is( $attr->type_constraint->name, 'Int', "$attr_name type is Int" );
}

# create genome track
my $hg38_dat = LoadFile($hg38_config_file);
my %hg38_genome_config;

for my $attr_href ( @{ $hg38_dat->{genome_sized_tracks} } ) {
  if ( $attr_href->{type} eq "genome" ) {
    for my $attr ( keys %{$attr_href} ) {
      $hg38_genome_config{$attr} = $attr_href->{$attr};
    }
  }
}
$hg38_genome_config{genome_chrs} = $hg38_dat->{genome_chrs};

use_ok('Seq::Build::GenomeSizedTrackStr');
my $hg38_gst = Seq::Build::GenomeSizedTrackStr->new( \%hg38_genome_config );
ok(
  (
         $hg38_gst
      && ( blessed $hg38_gst || !ref $hg38_gst )
      && $hg38_gst->isa('Seq::Build::GenomeSizedTrackStr')
  ),
  "Seq::Build::GenomeSizedTrackStr obj created"
);

# build the genome
{
  my %chr_lens = ();
  $hg38_gst->clear_genome_seq;
  $hg38_gst->build_genome;

}

sub does_role {
  my $package = shift;
  my $role    = shift;

  local $Test::Builder::Level = $Test::Builder::Level + 1;

  ok( $package->meta->does_role($role), "$package does the $role role" );
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
__END__

mysql --user=genome --host=genome-mysql.cse.ucsc.edu -A -D hg38 \
  -e "select * FROM hg38.knownGene LEFT JOIN hg38.kgXref ON hg38.kgXref.kgID = hg38.knownGene.name where hg38.knownGene.chrom = 'chr22';" \ 
  &> knownGene.txt
