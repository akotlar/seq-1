use 5.10.0;
use strict;
use warnings;

use Test::More qw(no_plan);
use Test::Moose::More;
use Seq::Statistics;

validate_class 'Seq::Statistics' => (
  isa        => ['Seq::Statistics::Base'],
  attributes => [
    statsKey => {
      is      => 'ro',
      isa     => 'Str',
      default => 'statistics',
    },
    ratioKey => {
      is      => 'ro',
      isa     => 'Str',
      default => 'ratios',
    },
    qcFailKey => {
      is      => 'ro',
      isa     => 'Str',
      default => 'qcFail',
    },
    debug => {
      is      => 'ro',
      isa     => 'Int',
      default => 0,
    }
  ],
  does => [
    'Seq::Statistics::Record', 'Seq::Statistics::Ratios',
    'Seq::Role::Message',      'Seq::Statistics::Store'
  ],
  methods   => ['summarize'],
  immutable => 1
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
