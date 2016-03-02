use 5.10.0;
use strict;
use warnings;

use Test::More qw(no_plan);
use Test::Moose::More;
use Seq::Statistics::Record;

validate_role 'Seq::Statistics::Record' => (
  required_methods => [ 'isBadFeature', 'statsKey', 'statsRecord', 'debug' ],
  attributes       => [
    countKey => {
      is      => 'rw',
      isa     => 'Str',
      lazy    => 1,
      default => 'count',
    },
    _transitionTypesHref => {
      is       => 'ro',
      isa      => 'HashRef[Int]',
      traits   => ['Hash'],
      handles  => { isTr => 'get', },
      default  => sub { return { AG => 1, GA => 1, CT => 1, TC => 1, R => 1, Y => 1 } },
      lazy     => 1,
      init_arg => undef
    },
    _transitionTransversionKeysAref => {
      is       => 'ro',
      isa      => 'ArrayRef[Str]',
      traits   => ['Array'],
      handles  => { trTvKey => 'get', },
      default  => sub { [ 'Transversions', 'Transitions' ] },
      lazy     => 1,
      init_arg => undef,
    },
    _snpAnnotationsAref => {
      is       => 'ro',
      isa      => 'ArrayRef[Str]',
      traits   => ['Array'],
      handles  => { snpKey => 'get', },
      default  => sub { [ 'noRs', 'rs' ] },
      lazy     => 1,
      init_arg => undef,
    }
  ],
  does    => [ 'Seq::Role::Genotypes', 'Seq::Role::Message' ],
  methods => [ 'record',               'storeCount', 'countCustomFeatures' ],
  compoase => 1
);
