use 5.10.0;
use strict;
use warnings;

use Test::More qw(no_plan);
use Test::Moose::More;
use Seq::Statistics::Percentiles::QualityControl;

validate_role 'Seq::Statistics::Percentiles::QualityControl' => (
  required_methods => [ 'allRatios', 'getPercVal', 'target', 'ratioName' ],
  attributes       => [
    qcFailKey => {
      is      => 'ro',
      isa     => 'Str',
      default => 'qcFail'
    },
    failMessage => {
      is      => 'ro',
      isa     => 'Str',
      default => 'outside 95th percentile'
    },
    preScreened => {
      is      => 'rw',
      isa     => 'ArrayRef[Str|Num]',
      traits  => ['Array'],
      handles => {
        blacklistID    => 'push',
        blacklistedIDs => 'elements',
      },
      default => sub { [] }
    },
  ],
  methods  => [ 'qc', ],
  compoase => 1
);
