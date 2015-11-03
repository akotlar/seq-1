# vars that are not initialized at construction
package Seq::Role::Message;

use 5.10.0;
use Moose::Role;
use Redis;
use strict;
use warnings;
use namespace::autoclean;
with 'MooX::Role::Logger';
use IO::AIO; #AnyEvent logger will use this
use Carp 'croak';

use Cpanel::JSON::XS;
use Coro;
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

has publishServerAddress => (
  is => 'ro',
  isa => 'Str',
  default => 'genome.local:6379',
);

has messangerHref => (
  is        => 'rw',
  isa       => 'HashRef',
  traits    => ['Hash'],
  required  => 0,
  predicate => 'hasPublisher',
  handles   => { getMsg => 'get' }
);

has messagePublisher => (
  is       => 'rw',
  required => 0,
  lazy     => 1,
  init_arg => undef,
  builder  => '_buildMessagePublisher',
  handles  => { _publish => 'publish' }
);

sub publishMessage {
  my ($self, $msg) = @_;
  if(!$self->hasPublisher) {return; }
  $self->getMsg('message')->{data} = $msg;
  $self->_publish($self->getMsg('channel'), encode_json($self->messangerHref) );
};

sub _buildMessagePublisher {
  my $self = shift;

  return Redis->new(server => $self->publishServerAddress);
}

sub tee_logger {
  my ($self, $log_method, $msg) = @_;
  $self->_logger->$log_method($msg);
  $self->publishMessage($msg) if $self->hasPublisher;

  if ( $log_method eq 'error' ) {
    confess $msg . "\n";
  } 
}

no Moose::Role;
1;
