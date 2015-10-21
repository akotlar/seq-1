use 5.10.0;
use strict;
use warnings;

package Seq::Config::Track;

our $VERSION = '0.001';

# ABSTRACT: A base class for track classes
# VERSION

use Moose 2;
use Moose::Util::TypeConstraints;
use MooseX::Types::Path::Tiny qw/ Path /;

use namespace::autoclean;
use Type::Params qw/ compile /;
use Types::Standard qw/ Str Object /;

with 'MooX::Role::Logger';

=property @public @required {Str} name

  The track name. This is defined directly in the input config file.

  @example:
  =for :list
  * gene
  * snp

=cut

has name => ( is => 'ro', isa => 'Str', required => 1, );

=method all_genome_chrs

  Returns all of the elements of the @property {ArrayRef<str>} C<genome_chrs>
  as an array (not an array reference).
  $self->all_genome_chrs

=cut

has genome_chrs => (
  is       => 'ro',
  isa      => 'ArrayRef[Str]',
  traits   => ['Array'],
  required => 1,
  handles  => { all_genome_chrs => 'elements', },
);

=method get_next_chr

  Returns all of the elements of the @property {ArrayRef<str>} C<next_chr>
  as a Str.
  $self->next_chr( )

=cut

has next_chr => (
  is      => 'ro',
  isa     => 'HashRef',
  traits  => ['Hash'],
  lazy    => 1,
  builder => '_build_next_chr',
  handles => { get_next_chr => 'get', },
);

has genome_index_dir => ( is => 'ro', isa => Path, coerce => 1, default => "index" );
has genome_raw_dir   => ( is => 'ro', isa => Path, coerce => 1, default => "raw" );

has local_files => (
  is      => 'ro',
  isa     => 'ArrayRef',
  default => sub { [] },
);

has remote_dir => ( is => 'ro', isa => 'Str' );
has remote_files => (
  is      => 'ro',
  isa     => 'ArrayRef',
  traits  => ['Array'],
  handles => { all_remote_files => 'elements', },
  default => sub { [] },
);

sub _build_next_chr {
  my $self = shift;

  my %next_chrs;
  my @chrs = $self->all_genome_chrs;
  for my $i ( 0 .. $#chrs ) {
    if ( defined $chrs[ $i + 1 ] ) {
      $next_chrs{ $chrs[$i] } = $chrs[ $i + 1 ];
    }
  }
  return \%next_chrs;
}

__PACKAGE__->meta->make_immutable;

1;
