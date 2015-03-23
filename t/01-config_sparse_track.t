#!perl -T
use 5.10.0;
use strict;
use warnings;
use Test::More;
use File::Copy;
use Scalar::Util qw( blessed );
use DDP;
use Lingua::EN::Inflect qw( A PL_N );

plan tests => 32;

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
    qw( local_dir local_file
    name type entry_names )
  );

has_rw_attr( $package, $_ ) for (qw( sql_statement ));

# check type constraints - Str
for my $attr_name (
    qw( local_dir local_file
    name sql_statement )
  )
{
    my $attr = $package->meta->get_attribute($attr_name);
    ok( $attr->has_type_constraint, "$package $attr_name has a type constraint" );
    is( $attr->type_constraint->name, 'Str', "$attr_name type is Str" );
}

# check type constraints - SparseTrackType
for my $attr_name (qw( type )) {
    my $attr = $package->meta->get_attribute($attr_name);
    ok( $attr->has_type_constraint, "$package $attr_name has a type constraint" );
    is( $attr->type_constraint->name,
        'SparseTrackType', "$attr_name type is SparseTrackType" );
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
