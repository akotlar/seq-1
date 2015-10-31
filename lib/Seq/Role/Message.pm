# vars that are not initialized at construction
package Seq::Role::Message;

use Moose::Role;
use Redis;
use strict;
use warnings;
use namespace::autoclean;
with 'MooX::Role::Logger';

use Coro;

has redisHost => (
  is => 'ro',
  isa => 'Str',
  default => 'genome.local',
);

has redisPort => (
  is => 'ro',
  isa => 'Str',
  default => '6379',
);

has messageChannelHref => (
  is        => 'ro',
  isa       => 'HashRef',
  traits    => ['Hash'],
  required  => 0,
  predicate => 'wants_to_publish_messages',
  handles   => { channelInfo => 'get' }
);

has _message_publisher => (
  is       => 'ro',
  required => 0,
  lazy     => 1,
  init_arg => undef,
  builder  => '_build_message_publisher',
  handles  => { _publishMessage => 'publish' }
);

sub _build_message_publisher {
  my $self = shift;

  return Redis->new( host => $self->redisHost, port => $self->redisPort );
}

sub tee_logger {
  my ( $self, $log_method, $msg ) = @_;

  async {
    if ( $self->wants_to_publish_messages ) {
      $self->_publish_message($_[0]);
    }
    cede;
  } $msg;

  $self->_logger->$log_method($msg);

  if ( $log_method eq 'error' ) {
    confess $msg . "\n";
  }
}

sub _publish_message {
  my ( $self, $message ) = @_;

  # TODO: check performance of the array merge benefit is indirection, cost may be too high?
  $self->publish( $self->channelInfo('messageChannel'),
    encode_json( { %{ $self->channelInfo('recordLocator') }, message => $message } ) );
}

no Moose::Role;
1;
