#!perl -T
use 5.10.0;
use strict;
use warnings;
use Scalar::Util qw( blessed );
use Test::More;
use YAML::XS qw( Dump );

plan tests => 20;

BEGIN {
  chdir("./sandbox");
}

my $package = "Seq::Build::SparseTrack";
say $package;

# load package
use_ok($package) || die "$package cannot be loaded";

# check package uses Moose
ok( $package->can('meta'), "$package has a meta() method" )
  or BAIL_OUT("$package does not have a meta() method.");

# check package attributes
{
  # check abs_pos attribute
  my $attr = $package->meta->get_attribute('abs_pos');
  ok( $attr->has_type_constraint,
    "$package attribute 'abs_pos' has a type constraint" );
  is( $attr->type_constraint->name, 'Int', "$package attribute 'abs_pos' is a 'Int'" );
}

# store data
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

__END__
