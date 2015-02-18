#!perl -T
use 5.10.0;
use strict;
use warnings;
use Scalar::Util qw( blessed );
use Test::More;
use YAML::XS qw( Dump );

plan tests => 21;

BEGIN
{
  chdir("./t");
}

my $package = "Seq::Build::SparseTrack";
say $package;

# load package
use_ok($package) || die "$package cannot be loaded";

# check package uses Moose
ok ($package->can('meta'), "$package has a meta() method")
  or BAIL_OUT("$package does not have a meta() method.");

# check package attributes
{
  # check type attribute
  my $attr = $package->meta->get_attribute('type');
  ok( $attr->has_type_constraint, "$package attribute 'type' has a type constraint");
  is( $attr->type_constraint->name, 'SparseTrackType', 
    "$package attribute 'type' is a 'SparseTrackType'");

  # check chr_pos attribute
  $attr = $package->meta->get_attribute('chr_pos');
  ok( $attr->has_type_constraint, "$package attribute 'chr_pos' has a type constraint");
  is( $attr->type_constraint->name, 'Str', "$package attribute 'chr_pos' is a 'Str'");
  
  # check features attribute
  $attr = $package->meta->get_attribute('features');
  ok( $attr->has_type_constraint, "$package attribute 'features' has a type constraint");
  is( $attr->type_constraint->name, 'HashRef', "$package attribute 'features' is a 'HashRef'");
}

# store data
{
  my $dbsnp = Seq::Build::SparseTrack->new( { type => 'snpLike', } );
  ok( ( $dbsnp && (blessed $dbsnp || !ref $dbsnp) 
      && $dbsnp->isa($package) ), "$package obj created");

  my @exp_history = ( );
  my $data = [
    { chr_pos => "chr1:100",
      features => { 
        maf => 0.1,
        alleles => 'A,C',
      }
    },
    { chr_pos => "chr2:200",
      features => { 
        maf => 0.2,
        alleles => 'A,G',
      }
    },
    { chr_pos => "chr3:300",
      features => { 
        maf => 0.3,
        alleles => 'A,T',
      }
    },
  ];

  for my $entry (@$data)
  {
    $dbsnp->chr_pos( $entry->{chr_pos} );
    $dbsnp->features( $entry->{features} );
    is_deeply( $dbsnp->save_site_and_seralize, $entry, 'seralized entry');
    $dbsnp->clear;
    is( $dbsnp->chr_pos, '', 'cleared chr_pos' );
    is_deeply( $dbsnp->features, {}, 'cleared features' );
    is( 1, $dbsnp->have_annotated_site( $entry->{chr_pos} ), 'history works');
  }
}
