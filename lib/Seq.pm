use 5.10.0;
use strict;
use warnings;

package Seq;

use Moose 2;

use Carp qw/ croak /;
use namespace::autoclean;
use Scalar::Util qw/ reftype /;

__PACKAGE__->meta->make_immutable;

1;
