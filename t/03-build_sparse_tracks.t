#!perl -T
use 5.10.0;
use strict;
use warnings;

use Lingua::EN::Inflect qw/ A PL_N /;
use IO::Uncompress::Gunzip qw( $GunzipError );
use Path::Tiny;
use Test::More;
use Scalar::Util qw/ blessed /;
use YAML qw/ LoadFile /;

use DDP;
use Data::Dump qw/ dump /;

plan tests => 13;

my $package = "Seq::Build::SparseTrack";
say $package;

# set test genome
my $ga_config   = path('./t/hg38_test.yml')->absolute->stringify;
my $config_href = LoadFile($ga_config);

# load package
use_ok($package) || die "$package cannot be loaded";

# check extends
check_isa( $package,
  [ 'Seq::Config::SparseTrack', 'Seq::Config::Track', 'Moose::Object' ] );

# check attributes and type constraints
my %attr_types = (
  genome_track_str      => 'Seq::Build::GenomeSizedTrackStr',
  counter               => 'Num',
  bulk_insert_threshold => 'Num',
  force                 => 'Bool',
);
for my $attr_name ( sort keys %attr_types ) {
  my $attr = $package->meta->get_attribute($attr_name);
  ok( $attr->has_type_constraint,
    "$package has attribute '$attr_name' with a type constraint" );
  is( $attr->type_constraint->name,
    $attr_types{$attr_name},
    "attribute '$attr_name' has type '$attr_types{$attr_name}'" );
}

exit;
# TODO: these tests are old and need updating
#       - create object
#       - emit data for storage
#       - _has_site_range_file() needs a test
#       - _get_range_list() needs a test

{
  my $dbsnp = Seq::Build::SparseTrack->new();
  ok( ( $dbsnp && ( blessed $dbsnp || !ref $dbsnp ) && $dbsnp->isa($package) ),
    "$package obj created" );

  my @exp_history = ();
  my $data        = [
    {
      abs_pos  => 100,
      features => {
        thing1 => 'good',
        thing2 => 'sublime',
      },
    },
    {
      abs_pos  => 200,
      features => { talks => 'sometimes', },
    },
    {
      abs_pos  => 300,
      features => { good_driver => 'very', },
    },
  ];

  for my $entry (@$data) {
    is(
      '',
      $dbsnp->have_annotated_site( $entry->{abs_pos} ),
      'history correctly does not find abs_pos'
    );
    $dbsnp->abs_pos( $entry->{abs_pos} );
    $dbsnp->features( $entry->{features} );
    is_deeply( $dbsnp->save_site_and_Serialize, $entry, 'Serialized entry' );
    $dbsnp->clear_all;
    is( $dbsnp->has_abs_pos, '',    'cleared attrib abs_pos' );
    is( $dbsnp->abs_pos,     undef, 'cleared abs_pos' );
    is(
      1,
      $dbsnp->have_annotated_site( $entry->{abs_pos} ),
      'history correcly finds abs_pos'
    );
  }
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

__END__
