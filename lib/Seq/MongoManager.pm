use 5.10.0;
use strict;
use warnings;

package Seq::MongoManager;
# ABSTRACT: Manages mongo db connections
# VERSION

use Moose 2;

with 'MooseX::Role::MongoDB', 'MooX::Role::Logger';

$MongoDB::BSON::looks_like_number = 1;

has default_database => (
  is  => 'ro',
  isa => 'Str',
);

has client_options => (
  is      => 'ro',
  isa     => 'HashRef',
  default => sub { { host => "mongodb://localhost" } }
);

sub _build__mongo_default_database { return $_[0]->default_database }
sub _build__mongo_client_options   { return $_[0]->client_options }

__PACKAGE__->meta->make_immutable;
