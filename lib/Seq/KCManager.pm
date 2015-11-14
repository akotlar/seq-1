use 5.10.0;
use strict;
use warnings;

package Seq::KCManager;

our $VERSION = '0.001';

# ABSTRACT: Manages KyotoCabinet db
# VERSION

=head1 DESCRIPTION

  @class B<Seq::KCManager>
  #TODO: Check description

  @example

Used in:
=for :list
* Seq::Annotate
* Seq::Build::GeneTrack

Extended by: None

=cut

use Moose 2;
use Moose::Util::TypeConstraints;

use Carp;
use Cpanel::JSON::XS;
use KyotoCabinet;
use Type::Params qw/ compile /;
use Types::Standard qw/ :types /;

enum db_type => [qw/ hash btree /];

with 'Seq::Role::IO';

has filename => (
  is       => 'ro',
  isa      => 'Str',
  required => 1,
);

# mode: - read or create
has mode => (
  is       => 'ro',
  isa      => 'Str',
  required => 1,
);

# bucket number for the file hash; KyotoCabinet docs indicate 50% to 400% of
# the number of stored elements should be used for optimal speed; this only
# needs to be set at creation
has bnum => (
  is      => 'ro',
  isa     => 'Int',
  default => 10_000_000,
);

# size of mapped memory - set for read/write
has msiz => (
  is      => 'ro',
  isa     => 'Int',
  default => 1_280_000_000,
);

has _db => (
  is      => 'ro',
  isa     => 'Maybe[KyotoCabinet::DB]',
  lazy    => 1,
  builder => '_build_db',
);

sub _build_db {
  my $self = shift;

  my $this_msiz = join "=", "msiz", $self->msiz;

  if ( $self->mode eq 'create' ) {
    my $this_bnum = join "=", "bnum", $self->bnum;

    # this option is recommended when creating a db with a prespecified bucket
    # number
    my $options          = "opts=HashDB::TLINEAR";
    my $params           = join "#", $options, $this_bnum;
    my $file_with_params = join "#", $self->filename, $params;
    my $db               = new KyotoCabinet::DB;

    if ( $db->open( $file_with_params, $db->OWRITER | $db->OCREATE ) ) {
      return $db;
    }
    else {
      printf STDERR "open error: %s\n", $db->error;
      return;
    }
  }
  elsif ( $self->mode eq 'read' ) {
    my $file_with_params = join "#", $self->filename, $this_msiz;
    my $db = new KyotoCabinet::DB;

    if ( $db->open( $file_with_params, $db->OREADER ) ) {
      return $db;
    }
    else {
      printf STDERR "open error: %s\n", $db->error;
      return;
    }
  }
  else {
    croak "ERROR: expected mode to be 'read' or 'create' but got: " . $self->mode;
  }
}

# db_put_string writes an entry for the key-value pair, which will overwrite
#   existing data and write the string
#   -> retrieve this data using db_get_string
sub db_put_string {
  my ( $self, $key, $string ) = @_;
  return $self->_db->set( $key, $string );
}

# db_get_string retireves the string for the given key
sub db_get_string {
  my ( $self, $key ) = @_;

  my $dbm = $self->_db;

  if ( defined $dbm ) {
    my $string = $dbm->get($key);

    if ( defined $string ) {
      return $string;
    }
    else {
      return;
    }
  }
  else {
    return;
  }
}

# rationale - hashes cannot really have duplicate keys; so, to circumvent this
# issue we'll check to see if there's data there at they key first, unpack it
# and add our new data to it and then store the merged data
sub db_put {
  my ( $self, $key, $href ) = @_;

  my $existing_aref = $self->db_get($key);

  if ( defined $existing_aref ) {
    my @data = @$existing_aref;
    push @data, $href;
    return $self->_db->set( $key, encode_json( \@data ) );
  }
  else {
    return $self->_db->set( $key, encode_json( [$href] ) );
  }
}

sub db_get {
  my ( $self, $keys ) = @_;

  # the reason we need to check the existance of the db has to do with that we
  # allow non-existant file names to be used in creating the object and since
  # the creation of the _db attribute is done in a lazy way we may never need to
  # bother checking the file system or opening the databse.
  my $dbm = $self->_db;

  # does dbm doesn't exist?
  my $val;
  if ( defined $dbm ) {
    if ( ref $keys eq 'ARRAY' ) {
      $val = $dbm->get_bulk($keys);
    }
    else { #singel key, scalar
      $val = $dbm->get($keys);
    }

    # does the value exist within the dbm?
    if ( defined $val ) {
      return decode_json $val;
    }
    else {
      return;
    }
  }
  else {
    return;
  }
}

__PACKAGE__->meta->make_immutable;

1;
