#!perl -T
use 5.10.0;
use strict;
use warnings;

use File::Copy;
use Lingua::EN::Inflect qw( A PL_N );
use Path::Tiny;
use Scalar::Util qw( blessed );
use Test::More;
use YAML qw/ LoadFile /;

use DDP; # for debugging

plan tests => 28;

# set test genome
my $ga_config  = path('./config/hg38.yml')->absolute->stringify;
my $config_href = LoadFile( $ga_config );

# set package name
my $package = "Seq::Config::Track";

# load package
use_ok($package) || die "$package cannot be loaded";

my $href = build_obj_data( 'genome_sized_tracks', 'genome', $config_href );
my $obj = $package->new( $href );

# attribute tests
my @ro_attrs = qw/ name genome_chrs next_chr genome_index_dir genome_raw_dir
                  local_files remote_dir remote_files /;
for my $attr ( @ro_attrs ) {
  has_ro_attr( $package, $attr );
}

my @paths = qw/ genome_index_dir genome_raw_dir /;
for my $attr ( @paths ) {
  is( $obj->$attr, path($config_href->{$attr})->stringify, "attr: $attr");
}

# Method tests
{
  my $exp_next_chrs_href = {
      chrM  =>  "chrX",
      chrX  =>  "chrY",
      chrY  =>  undef,
      chr1  =>  "chr2",
      chr2  =>  "chr3",
      chr3  =>  "chr4",
      chr4  =>  "chr5",
      chr5  =>  "chr6",
      chr6  =>  "chr7",
      chr7  =>  "chr8",
      chr8  =>  "chr9",
      chr9  =>  "chr10",
      chr10 =>  "chr11",
      chr11 =>  "chr12",
      chr12 =>  "chr13",
      chr13 =>  "chr14",
      chr14 =>  "chr15",
      chr15 =>  "chr16",
      chr16 =>  "chr17",
      chr17 =>  "chr18",
      chr18 =>  "chr19",
      chr19 =>  "chr20",
      chr20 =>  "chr21",
      chr21 =>  "chr22",
      chr22 =>  "chrM",
  };
  my %obs_result;
  for my $chr ( @{$config_href->{genome_chrs}} ) {
    $obs_result{$chr} = $obj->get_next_chr( $chr );
  }
  is_deeply( $exp_next_chrs_href, \%obs_result, 'method: get_next_chr');
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
