#!perl -T
use 5.10.0;
use strict;
use warnings;
use Test::More;
use Cwd;
use YAML::XS qw(Dump LoadFile);
use DBD::Mock;
use Test::Exception;

plan tests => 46;

BEGIN
{
  chdir("./t");
}

# test the package's attributes and type constraints
my $package = "Seq::Build::GenomeSizedTrack";

# load package
use_ok($package) || die "$package cannot be loaded";

# check package uses Moose
ok( $package->can('meta'), "$package has a meta() method" )
  or BAIL_OUT("$package does not have a meta() method.");

# check type constraints for attributes that should have Str values
for my $attr_name (qw( name ))
{
  my $attr = $package->meta->get_attribute($attr_name);
  ok( $attr->has_type_constraint, "$package $attr_name has a type constraint");
  is( $attr->type_constraint->name, 'Str', "$attr_name type is Str" );
}

# check type constraints for attributes that should have Int values
for my $attr_name (qw( length ))
{
  my $attr = $package->meta->get_attribute($attr_name);
  ok( $attr->has_type_constraint, "$package $attr_name has a type constraint");
  is( $attr->type_constraint->name, 'Int', "$attr_name type is Int" );
}

# check type constraints for attributes that should have Int values
for my $attr_name (qw( str_seq ))
{
  my $attr = $package->meta->get_attribute($attr_name);
  ok( $attr->has_type_constraint, "$package $attr_name has a type constraint");
  is( $attr->type_constraint->name, 'ScalarRef[Str]', "$attr_name type is ScalarRef[Str]" );
}

# check type constraints for attributes that should have Int values
for my $attr_name (qw( char2score score2char ))
{
  my $attr = $package->meta->get_attribute($attr_name);
  ok( $attr->has_type_constraint, "$package $attr_name has a type constraint");
  is( $attr->type_constraint->name, 'CodeRef', "$attr_name type is CodeRef" );
}
