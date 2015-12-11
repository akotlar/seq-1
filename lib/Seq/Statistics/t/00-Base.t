use 5.10.0;
use strict;
use warnings;

use Test::More qw(no_plan);
use Test::Moose::More;
use Seq::Statistics::Base;

validate_class 'Seq::Statistics::Base' => (
  attributes => [
    statsRecord => {
      is      => 'rw',
      isa     => 'HashRef',
      traits  => ['Hash'],
      handles => {
        getStat     => 'get',
        setStat     => 'set',
        hasStat     => 'exists',
        statsKv     => 'kv',
        statSamples => 'keys',
        hasStats    => 'keys',
      },
      init_arg => undef,
      #won't give correct ref default  => sub { return {} },
    },
    disallowedFeatures => {
      is      => 'ro',
      traits  => ['Hash'],
      isa     => 'HashRef[Str]',
      handles => { isBadFeature => 'exists', },
    },
  ],
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
