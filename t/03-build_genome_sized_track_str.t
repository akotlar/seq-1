#!perl -T
use 5.10.0;
use strict;
use warnings;

use Lingua::EN::Inflect qw( A PL_N );
use Path::Tiny;
use Scalar::Util qw( blessed );
use Test::More;
use YAML qw/ LoadFile /;

use Data::Dump qw/ dump /;
plan tests => 8;

# set test genome
my $ga_config  = path('./config/hg38.yml')->absolute->stringify;
my $config_href = LoadFile( $ga_config );

# test the package's attributes and type constraints
my $package = "Seq::Build::GenomeSizedTrackStr";

# load package
use_ok($package) || die "$package cannot be loaded";

# check package extends Seq::Config::GenomeSizedTrack which is a Moose::Object
check_isa( $package,
  [ 'Seq::Config::GenomeSizedTrack', 'Seq::Config::Track', 'Moose::Object' ] );

# check type constraints for attributes that should have Str values
for my $attr_name (qw( genome_seq )) {
  my $attr = $package->meta->get_attribute($attr_name);
  ok( $attr->has_type_constraint, "$package $attr_name has a type constraint" );
  is( $attr->type_constraint->name, 'Str', "$attr_name type is Str" );
}

# TODO: obj creation and beyond fails b/c it expects to build the string genome
#       from the files supplied by local files
# object creation
TODO: {
  local $TODO = 'build an object - must have seq data on disk to do this';
  my $seq = '';
  my %chr_len;
  for my $chr ( @{ $config_href->{genome_chrs} } ) {
    my $char_seq = "A" x int(rand(10) + 1);
    $seq .= $char_seq;
    $chr_len{$chr} = length $char_seq;
  }
  my $href = build_obj_data( 'genome_sized_tracks', 'genome', $config_href );
  $href->{char_seq} = \$seq;
  $href->{chr_len}  = \%chr_len;
  my $obj = $package->new( $href );
  ok($obj, 'object creation');
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
