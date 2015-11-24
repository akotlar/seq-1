use 5.10.0;
use strict;
use warnings;

use Data::Dump qw/ dump /;
use Path::Tiny;
use Test::More qw(no_plan);
use Test::Moose::More;
use Seq::Statistics::Percentiles;

validate_class 'Seq::Statistics::Percentiles' => (
  attributes => [
    percentilesKey => {
    is      => 'ro',
    isa     => 'Str',
    default => 'percentiles',
  },
  percentileThresholdNames => {
    is      => 'ro',
    traits  => ['Array'],
    isa     => 'ArrayRef[Str]',
    #won't return correct memory address  default => sub { return [ '5th', 'median', '95th' ] },
    handles => { getThresholdName => 'get', }
  },
  percentileThresholds => {
    is      => 'ro',
    traits  => ['Array'],
    isa     => 'ArrayRef[Num]',
    #won't return correct memory address default => sub { return [ .05, .50, .95 ] },
    handles => {
      getThreshold  => 'get',
      allThresholds => 'elements',
    }
  },
  ratios => {
    is      => 'rw',
    isa     => 'ArrayRef[ArrayRef[Str|Num]]',
    traits  => ['Array'],
    handles => {
      removeRatio => 'splice',
      sortRatios  => 'sort_in_place',
      getRatioID  => 'get',
      getRatio    => 'get',
      numRatios   => 'count',
      allRatios   => 'elements',
    },
    required => 1,
    },
    lastRatioIdx => {
      is      => 'ro',
      isa     => 'Num',
      lazy    => 1,
      builder => '_buildNumRatios',
    },
    percentiles => {
      is      => 'rw',
      isa     => 'ArrayRef[ArrayRef[Str|Num]]',
      traits  => ['Array'],
      handles => {
        setPercentile  => 'push',
        getPercName    => 'get',
        getPercVal     => 'get',
        numPercentiles => 'count',
        hasPercentiles => 'count',
      },
      required => 1,
      #won't return correct memory address default  => sub { return [] },
      init_arg => undef,
    },
    ratioName => {
      is       => 'ro',
      isa      => 'Str',
      required => 1,
    },
    target => {
      is       => 'rw',
      isa      => 'HashRef',
      traits   => ['Hash'],
      handles  => { addToTarget => 'set', },
      required => 1,
    },
    debug => {
      is      => 'ro',
      isa     => 'Int',
      default => 0,
    },
  ],
  does      => ['Seq::Statistics::Percentiles::QualityControl',],
  methods   => [ 'BUILD', 'makePercentiles', 'storeAndQc', 'screenRatios',
    '_calcPercentile'
  ],
  immutable => 1,
);


# my $hRef = {
#   SL58494 => {
#     Exonic => {
#       'Non-Coding' => { statistics => { count => 7 } },
#       Replacement  => { statistics => { count => 4 } },
#       Silent       => { statistics => { count => 1 } },
#       statistics   => { count      => 12 }
#     },
#     Intronic => {
#       'Non-Coding' => { statistics => { count => 1 } },
#       statistics   => { count      => 1 }
#     },
#     statistics    => { count      => 13 },
#     Transitions   => { statistics => { count => 24 } },
#     Transversions => { statistics => { count => 15 } }
#   }
# };

# my $hRef2 = {
#   SL54554 => {
#     Exonic => {
#       'Non-Coding' => { statistics => { count => 1 } },
#       Replacement  => { statistics => { count => 2 } },
#       Silent       => { statistics => { count => 2 } },
#       statistics   => { count      => 5 }
#     },
#     statistics    => { count      => 5 },
#     Transitions   => { statistics => { count => 12 } },
#     Transversions => { statistics => { count => 3 } }
#   }
# };
