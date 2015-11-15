package Seq::Role::Message;

our $VERSION = '0.001';

# ABSTRACT: A class for communicating
# VERSION

# vars that are not initialized at construction

use 5.10.0;
use Moose::Role;
use Redis::hiredis;
use strict;
use warnings;
use namespace::autoclean;
with 'MooX::Role::Logger';
use Carp 'croak';

use Coro;
use Cpanel::JSON::XS;
use DDP;

# my $singleton;

# sub instance {
#   return $singleton //= Seq::Role::Message->new();
# }

# # to protect against people using new() instead of instance()
# around 'new' => sub {
#     my $orig = shift;
#     my $self = shift;
#     return $singleton //= $self->$orig(@_);
# };

# sub initialize {
#     defined $singleton
#       and croak __PACKAGE__ . ' singleton has already been instanciated';
#     shift;
#     return __PACKAGE__->new(@_);
# }

#note: not using native traits because they don't support Maybe attrs
has publisherAddress => (
  is       => 'ro',
  isa      => 'Maybe[ArrayRef]',
  required => 0,
  lazy     => 1,
  default  => undef,
);

#note: not using native traits because they don't support Maybe attrs
has messanger => (
  is       => 'rw',
  isa      => 'Maybe[HashRef]',
  required => 0,
  lazy     => 1,
  default  => undef,
);

has publisher => (
  is        => 'ro',
  required  => 0,
  lazy      => 1,
  init_arg  => undef,
  builder   => '_buildMessagePublisher',
  lazy      => 1,
  predicate => 'hasPublisher',
  handles   => { notify => 'command' },
);

sub _buildMessagePublisher {
  my $self = shift;
  return unless $self->publisherAddress;
  #delegation doesn't work for Maybe attrs
  return Redis::hiredis->new(
    host => $self->publisherAddress->[0],
    port => $self->publisherAddress->[1],
  );
}

#note, accessing hash directly because traits don't work with Maybe types
sub publishMessage {
  my ( $self, $msg ) = @_;
  #because predicates don't trigger builders, need to check hasPublisherAddress
  return unless $self->messanger && $self->publisherAddress;
  $self->messanger->{message}{data} = $msg;
  $self->notify(
    [ 'publish', $self->messanger->{event}, encode_json( $self->messanger ) ] );
}

sub tee_logger {
  my ( $self, $log_method, $msg ) = @_;
  $self->publishMessage($msg);

  async {
    $self->_logger->$log_method($msg);
  }
  # redundant, _logger should handle exceptions
  # if ( $log_method eq 'error' ) {
  #   confess $msg . "\n";
  # }
}

no Moose::Role;
1;
