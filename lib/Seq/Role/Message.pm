# vars that are not initialized at construction
package Seq::Role::Message;

use Moose::Role;
use Redis;
use strict;
use warnings;
use namespace::autoclean;
with 'MooX::Role::Logger';

use Coro;

has publishServerAddress => (
  is => 'ro',
  isa => 'Str',
  default => 'genome.local:6379',
);

has messageChannelHref => (
  is        => 'ro',
  isa       => 'HashRef',
  traits    => ['Hash'],
  required  => 0,
  predicate => 'hasPublisher',
  handles   => { channelInfo => 'get' }
);

# later we can brek this out into separate role, 
# and this publisher will be located in Message.pm, with a separate role
# handling implementation
has _message_publisher => (
  is       => 'ro',
  required => 0,
  lazy     => 1,
  init_arg => undef,
  builder  => '_buildMessagePublisher',
  handles  => { publishMessage => 'publishMessage' }
);

sub _buildMessagePublisher {
  my $self = shift;

  return Redis->new(server => $self->publishServerAddress);
}

sub tee_logger {
  my ( $self, $log_method, $msg ) = @_;

  async {
    if ($self->hasPublisher) {
      $self->publishMessage($_[0]);
    }
    cede;
  } $msg;

  $self->_logger->$log_method($msg);

  if ( $log_method eq 'error' ) {
    confess $msg . "\n";
  }
}

sub publishMessage {
  my ( $self, $message ) = @_;

  # TODO: check performance of the array merge benefit is indirection, cost may be too high?
  $self->publish(
    $self->channelInfo('messageChannel'),
    encode_json( 
      { %{ $self->channelInfo('recordLocator') }, message => $message } 
    )
  );
}

no Moose::Role;
1;
