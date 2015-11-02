# vars that are not initialized at construction
package Seq::Role::Message;

use 5.10.0;
use Moose::Role;
use Redis;
use strict;
use warnings;
use namespace::autoclean;
with 'MooX::Role::Logger';

use Cpanel::JSON::XS;
use Coro;

has publishServerAddress => (
  is => 'ro',
  isa => 'Str',
  default => 'genome.local:6379',
);

has messangerHref => (
  is        => 'ro',
  isa       => 'HashRef',
  traits    => ['Hash'],
  required  => 0,
  predicate => 'hasPublisher',
  handles   => { messanger => 'get' }
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
  handles  => { publishMessage => 'publish' }
);

around 'publishMessage' => sub {
  my ($orig, $self, $message ) = @_;

  say "publishMessage run with $message";
  if(!$self->hasPublisher) {
    $self->log('warn', 'Attempted to publish message with no publisher');
  }

  $self->messanger('message')->{data} = $message;
  $self->$orig($self->messanger('channel'), encode_json($self->messangerHref) );
};

sub _buildMessagePublisher {
  my $self = shift;

  return Redis->new(server => $self->publishServerAddress);
}

sub tee_logger {
  my ( $self, $log_method, $msg ) = @_;
  
  $self->publishMessage($msg);
  async {
    $_[0]->_logger->${$_[1]}($_[2]);
    cede;
  } $self, $log_method, $msg;

  if ( $log_method eq 'error' ) {
    cede; #write messages to disc
    confess $msg . "\n";
  }
}

sub log {
  my ($self, $log_method, $msg) = @_;
  
  async {
    $_[0]->_logger->${$_[1]}($_[2]);
    cede;
  } $self, $log_method, $msg;

  if ( $log_method eq 'error' ) {
    cede; #write messages to disc
    confess $msg . "\n";
  }
}

no Moose::Role;
1;
