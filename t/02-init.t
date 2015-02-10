#!perl -T
use 5.10.0;
use strict;
use warnings;
use Test::More;
use YAML::XS qw(LoadFile);

plan tests => 20;

# test the package's attributes and type constraints
my $package = "Seq::Config::Init";

# load package
use_ok($package) || die "$package cannot be loaded";

# check package uses Moose
ok( $package->can('meta'), "$package has a meta() method" )
  or BAIL_OUT("$package does not have a meta() method.");

# check type constraints for attributes that should have Str values
for my $attr_name (qw( dsn host user password socket  ))
{
  my $attr = $package->meta->get_attribute($attr_name);
  ok( $attr->has_type_constraint, "$package $attr_name has a type constraint");
  is( $attr->type_constraint->name, 'Str', "$attr_name type is Str" );
}

# check type constraints for attributes that should have Int values
for my $attr_name (qw( port act verbose ))
{
  my $attr = $package->meta->get_attribute($attr_name);
  ok( $attr->has_type_constraint, "$package $attr_name has a type constraint");
  is( $attr->type_constraint->name, 'Int', "$attr_name type is Int" );
}

# check type constraints for attributes that should have Seq::Config values
{
  my $attr = $package->meta->get_attribute('config');
  ok( $attr->has_type_constraint, "$package 'config' has a type constraint");
  is( $attr->type_constraint->name, 'Seq::Config', "'config' type is Seq::Config" );
}


