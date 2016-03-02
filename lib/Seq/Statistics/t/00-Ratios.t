use 5.10.0;
use strict;
use warnings;

use Test::More qw(no_plan);
use Test::Moose::More;
use Seq::Statistics::Ratios;

validate_role 'Seq::Statistics::Ratios' => (
  required_methods => [ 'statsKey', 'countKey', 'ratioKey', 'statsKv', 'debug' ],
  attributes       => [
    ratioFeaturesRef => {
      is      => 'ro',
      traits  => ['Hash'],
      isa     => 'HashRef[ArrayRef[Str]]',
      handles => {
        ratioNumerators   => 'keys',
        ratioFeaturesKv   => 'kv',
        allowedNumerator  => 'exists',
        getDenomRatioKeys => 'get',
      },
      builder => '_buildRatioFeaturesRef'
    },
    ratiosHref => {
      is      => 'rw',
      isa     => 'HashRef[ArrayRef]',
      traits  => ['Hash'],
      handles => {
        allRatiosKv  => 'kv',
        allRatioVals => 'values',
        getRatios    => 'get',
        hasRatios    => 'defined',
        setRatios    => 'set',
        hasNoRatios  => 'is_empty',
      }
    }
  ],
  does     => [],
  methods  => [ 'makeRatios', '_recursiveCalc', '_calcRatio', '_nestedVal' ],
  compoase => 1
);
