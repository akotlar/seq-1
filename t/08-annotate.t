#!perl -T
use 5.10.0;
use strict;
use warnings;

use Data::Dump qw/ dump /;
use Lingua::EN::Inflect qw/ A PL_N /;
use Path::Tiny;
use Test::More;
use YAML qw/ LoadFile /;

plan tests => 46;

my %attr_2_type = (
  _genome        => 'Seq::GenomeBin',
  _genome_scores => 'ArrayRef[Maybe[Seq::GenomeBin]]',
  _genome_cadd   => 'ArrayRef[Maybe[Seq::GenomeBin]]',
  _cadd_lookup   => 'HashRef',
  dbm_gene       => 'ArrayRef[ArrayRef[Maybe[Seq::KCManager]]]',
  dbm_snp        => 'ArrayRef[ArrayRef[Maybe[Seq::KCManager]]]',
  # dbm_tx         => 'ArrayRef[Seq::KCManager]',
  _header        => 'ArrayRef',
  has_cadd_track => 'Bool',

);
my %attr_to_is = map { $_ => 'ro' } ( keys %attr_2_type );
$attr_to_is{has_cadd_track} = 'rw';

# set test genome
my $ga_config   = path('./t/hg38_test.yml')->absolute->stringify;
my $config_href = LoadFile($ga_config);

# set package name
my $package = "Seq::Annotate";

# load package
use_ok($package) || die "$package cannot be loaded";

# check extension of
check_isa( $package, [ 'Seq::Assembly', 'Moose::Object' ] );

# check roles
does_role( $package, 'MooX::Role::Logger' );

# check attributes, their type constraint, and 'ro'/'rw' status
for my $attr_name ( sort keys %attr_2_type ) {
  my $exp_type = $attr_2_type{$attr_name};
  my $attr     = $package->meta->get_attribute($attr_name);
  ok( $attr->has_type_constraint, "$package $attr_name has a type constraint" );
  is( $attr->type_constraint->name, $exp_type, "$attr_name type is $exp_type" );

  # check 'ro' / 'rw' status
  if ( $attr_to_is{$attr_name} eq 'ro' ) {
    has_ro_attr( $package, $attr_name );
  }
  elsif ( $attr_to_is{$attr_name} eq 'rw' ) {
    has_rw_attr( $package, $attr_name );
  }
  else {
    printf( "ERROR - expect 'ro' or 'rw' but got '%s'", $attr_to_is{$attr_name} );
    exit(1);
  }
}
SKIP: {
  my $reason = 'did not have required data on disk to test build methods';
  skip $reason, 1 unless Have_chr_files($config_href);
  my $obj = $package->new_with_config( { configfile => $ga_config } );
  ok( $obj, 'object creation' );
}

# Methods tests

###############################################################################
# sub routines
###############################################################################

sub Have_chr_files {
  my $config_href   = shift;
  my $missing_files = 0;

  for my $track ( @{ $config_href->{genome_sized_tracks} } ) {

    if ( $track->{type} eq "genome" ) {
      #interestingly when the test runs $track->{local_files} is not a hash ref
      for my $file ( keys $track->{local_files} ) {
        my $pt = path( $config_href->{genome_raw_dir} )->child($file);
        $missing_files++ unless $pt->is_file;
      }
    }
  }

  if ($missing_files) {
    return;
  }
  else {
    return 1;
  }
}

sub build_obj_data {
  my ( $track_type, $type, $href ) = @_;

  my %hash;

  # get essential stuff
  for my $track ( @{ $config_href->{$track_type} } ) {
    if ( $track->{type} eq $type ) {
      for my $attr (qw/ name type local_files remote_dir remote_files /) {
        $hash{$attr} = $track->{$attr} if exists $track->{$attr};
      }
    }
  }

  # add additional stuff
  if (%hash) {
    $hash{genome_raw_dir}   = $config_href->{genome_raw_dir}   || 'sandbox';
    $hash{genome_index_dir} = $config_href->{genome_index_dir} || 'sandbox';
    $hash{genome_chrs}      = $config_href->{genome_chrs};
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
