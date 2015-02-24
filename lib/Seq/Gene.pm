package Seq::Gene;

use 5.10.0;
use Carp qw( croak );
use Moose;
use namespace::autoclean;

# has features of a gene and will run through the sequence
# build features will be implmented in Seq::Build::Gene that can build GeneSite
# objects
# would be useful to extend to have capcity to build peptides

__PACKAGE__->meta->make_immutable;

1; # End of Seq::GeneTrack
