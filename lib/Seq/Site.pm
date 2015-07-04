use 5.10.0;
use strict;
use warnings;

package Seq::Site;
# ABSTRACT: Base class for seralizing all sites.
# VERSION
=head1 DESCRIPTION
  
  @class B<Seq::Site>
  #TODO: Check description

  @example

Used in: None

Extended in:
=for :list
* Seq::Site::Gene
* Seq::Site::Snp

=cut

use Moose 2;
use Moose::Util::TypeConstraints;

use namespace::autoclean;

enum reference_base_types => [qw( A C G T N )];

has abs_pos => (
  is       => 'ro',
  isa      => 'Int',
  required => 1,
);

has ref_base => (
  is       => 'ro',
  isa      => 'reference_base_types',
  required => 1,
);

__PACKAGE__->meta->make_immutable;

1;
