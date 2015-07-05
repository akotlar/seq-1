#!perl -T
use 5.10.0;
use strict;
use warnings;

use DDP;
use File::Copy;
use Lingua::EN::Inflect qw( A PL_N );
use Path::Tiny;
use Scalar::Util qw( blessed );
use Test::More;
use YAML qw/ LoadFile /;

plan tests => 60;

# set test genome
my $ga_config  = path('./config/hg38.yml')->absolute->stringify;
my $config_href = LoadFile( $ga_config );

# set package name
my $package = "Seq::Config::GenomeSizedTrack";

# load package
use_ok($package) || die "$package cannot be loaded";

sub build_obj_data {
  my $href = shift;

  my %hash;

  # get essential stuff
  for my $track ( @{ $config_href->{genome_sized_tracks} } ) {
    if ( $track->{type} eq "genome") {
      %hash = map { $_ => $track->{$_} } (qw/ local_dir local_files name remote_dir remote_files type /);
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

my $href = build_obj_data( $config_href );

my $obj = $package->new( $href );

p $obj;
say $obj->genome_raw_dir;
say $obj->local_dir;
say $obj->genome_index_dir;
say $obj->genome_str_file;
say $obj->genome_bin_file;

for my $file ( $obj->all_raw_genome_files ) {
  say $file;
}

exit; # TODO: remove exit after debugging finished;

# check is moose object
check_isa( $package, ['Moose::Object'] );

# check package uses Moose
ok( $package->can('meta'), "$package has a meta() method" )
  or BAIL_OUT("$package does not have a meta() method.");

# check read-only attribute have read but no write methods
has_ro_attr( $package, $_ ) for ( qw ( name type genome_chrs local_dir local_files remote_dir remote_files ) );

# check type constraints - Str
for my $attr_name (qw( name local_dir remote_dir )) {
  my $attr = $package->meta->get_attribute($attr_name);
  ok( $attr->has_type_constraint, "$package $attr_name has a type constraint" );
  is( $attr->type_constraint->name, 'Str', "$attr_name type is Str" );
}

# check type constraints - ArrayRef[Str]
for my $attr_name ( qw( genome_chrs local_files remote_files ) ) {
  my $attr = $package->meta->get_attribute($attr_name);
  ok( $attr->has_type_constraint, "$package $attr_name has a type constraint" );
  is( $attr->type_constraint->name,
    'ArrayRef[Str]', "$attr_name type is ArrayRef[Str]" );
}

# check type constraints - GenomeSizedTrackType
for my $attr_name (qw( type )) {
  my $attr = $package->meta->get_attribute($attr_name);
  ok( $attr->has_type_constraint, "$package $attr_name has a type constraint" );
  is( $attr->type_constraint->name,
    'GenomeSizedTrackType', "$attr_name type is GenomeSizedTrackType" );
}

# check methods
#   1 - index coding:   get_idx_code
#   2 - index decoding: get_idx_base, get_idx_in_gan, get_idx_in_gene, get_idx_in_exon,
#                       get_idx_in_snp
{
  my ( %idx_codes, %idx_base, %idx_in_gan, %idx_in_gene, %idx_in_exon, %idx_in_snp );
  my %base_char_2_txt = ( '0' => 'N', '1' => 'A', '2' => 'C', '3' => 'G', '4' => 'T' );
  my @in_gan  = qw/ 0 8 /; # is gene annotated
  my @in_exon = qw/ 0 16 /;
  my @in_gene = qw/ 0 32 /;
  my @in_snp  = qw/ 0 64 /;

  # store vals for testing
  my ( %exp, %obs);
  foreach my $base_char ( keys %base_char_2_txt ) {
    foreach my $snp (@in_snp) {
      foreach my $gene (@in_gene) {
        foreach my $exon (@in_exon) {
            foreach my $gan (@in_gan) {
            my $char_code = $base_char + $gan + $gene + $exon + $snp;
            my $txt_base  = $base_char_2_txt{$base_char};

            # gather base codes
            push @{ $exp{base} }, $package->get_idx_base($char_code);
            push @{ $obs{base} }, $txt_base;

            # gather in gene annotation codes
            push @{ $exp{gan} }, $package->get_idx_in_gan($char_code);
            push @{ $obs{gan} }, ($gan ? 1 : 0);

            # gather in gene codes
            push @{ $exp{gene} }, $package->get_idx_in_gene($char_code);
            push @{ $obs{gene} }, ($gene ? 1 : 0);

            # gather in exon codes
            push @{ $exp{exon} }, $package->get_idx_in_exon($char_code);
            push @{ $obs{exon} }, ($exon ? 1 : 0);

            # gather in snp codes
            push @{ $exp{snp} }, $package->get_idx_in_snp($char_code);
            push @{ $obs{snp} }, ($snp ? 1 : 0);
          }
        }
      }
    }
  }

  # check build idx codes
  for my $type ( qw/ base gan gene exon snp / ) {
    is_deeply( $exp{$type}, $obs{$type}, "got idx correct index codes for $type" );
  }
}

p $package;

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
