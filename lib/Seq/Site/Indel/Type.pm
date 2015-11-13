use strict;
use warnings;
package Seq::Site::Indel::Type;

# use Moose;
# use MooseX::Types -declare => [qw/Indel/];

# use MooseX::Types::Moose qw(Str);
# use if MooseX::Types->VERSION >= 0.42, 'namespace::autoclean';

# use Seq::Site::Indel::Definition;

# class_type Indel, { class => 'Seq::Site::Indel::Definition' };

# coerce Indel, from Str, via {Seq::Site::Indel::Definition->new($_)};

use Moose::Util::TypeConstraints;
class_type 'Indel', { class => 'Seq::Site::Indel::Definition' };
coerce 'Indel',
  from 'Str',
  via { 
    require Seq::Site::Indel::Definition; 
    Seq::Site::Indel::Definition->new(minor_allele => $_)
  };

subtype 'Indels' => as 'ArrayRef[Indel]';

coerce 'Indels',
  from 'Indel',
  via {
    [$_]
  },
  from 'ArrayRef[Str]',
  via { 
    require Seq::Site::Indel::Definition;
    [ map { Seq::Site::Indel::Definition->new(minor_allele => $_) } @$_ ] 
  },
  from 'Str',
  via { 
    require Seq::Site::Indel::Definition; 
    Seq::Site::Indel::Definition->new(minor_allele => $_)
  };

1;