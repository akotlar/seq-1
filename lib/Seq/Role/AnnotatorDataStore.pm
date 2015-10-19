use strict;
use warnings;
use feature "state";

package Seq::Role::AnnotatorDataStore;

our $VERSION = '0.001';

# ABSTRACT: Builds a plain text genome used for binary genome creation
# VERSION
use Moose::Role;
use Carp qw/ croak /;
use Path::Tiny qw/ path /;
use namespace::autoclean;
use Type::Params qw/ compile /;
use Types::Standard qw/ :types /;

use DDP;

use threads;
use threads::shared;

# since we cannot insantiate a role, we may not need this...all variables may be class varialbes
# however, moose role attributes are composed into the including class, suggesting this may still be needed

# a class variable holding our thread-shared data
my $_genomeDataHref : shared = shared_clone( {} );

has _genomeDataHref => (
  traits   => ['Hash'],
  is       => 'rw',
  isa      => 'HashRef',
  handles  => { hasSeq => 'exists', getSeq => 'get', storeSeq => 'set' },
  init_arg => undef,
  default => sub { return $_genomeDataHref; }
);

my $shared_count : shared = 0; #debug, to be removed
my $count : shared        = 0; #debug, to be removed

sub load_track_data {
  state $check =
    compile( Object, Str, Str ); #self, $track_file_name, $sequence_file_parent_path
  my ( $self, $track_file_name, $track_file_folder ) = $check->(@_);

  $count += 1;
  print "\nTotal count run $count\n";

  if ( $self->hasSeq($track_file_name) ) #$track_file_name acts as hash key
  {
    $shared_count += 1;
    print "\nShared the data $shared_count times.\n";

    if ( is_shared( $self->getSeq($track_file_name)->[0] ) ) {
      print "\nThe data of the $track_file_name index 0 key is shared\n";
    }

    #returns anonymous array [\$seq,$track_length]
    return $self->getSeq($track_file_name);
  }

  # Alex, could you describe what you're doing here? to provide context for your
  # comment: if we need finer control, like per property, use threads::sempahore
  lock( $self->{_genomeDataHref} );

  my $track_file_path = path( $track_file_folder, $track_file_name )->stringify;

  my $track_fh = $self->get_read_fh($track_file_path);
  binmode $track_fh;

  my $track_length = -s $track_file_path;

  my $seqRef : shared = shared_clone( [] );

  $seqRef->[0] = '';
  $seqRef->[1] = $track_length;

  # error check the idx_file
  croak "ERROR: expected file: '$track_file_path' is empty." unless $track_length;

  read $track_fh, $seqRef->[0], $track_length;

  $self->storeSeq( $track_file_name, $seqRef );

  return $seqRef;
}

no Moose::Role;

1;
