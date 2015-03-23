use 5.10.0;
use strict;
use warnings;

package Seq::Role::ConfigFromFile;
# ABSTRACT: A moose role for configuring a class from a YAML file
# VERSION

use Moose::Role 2;
use MooseX::Types::Path::Tiny qw/ Path /;

use Carp qw/ croak /;
use namespace::autoclean;
use Type::Params qw/ compile /;
use Types::Standard qw/ :types /;
use Scalar::Util qw/ reftype /;
use YAML::XS qw/ Load /;

with 'Seq::Role::IO';

has configfile => (
  is        => 'ro',
  isa       => Path | Undef,
  coerce    => 1,
  predicate => 'has_configfile',
  eval "require MooseX::Getopt; 1" ? ( traits => ['Getopt'] ) : (),
);

sub new_with_config {
  state $check = compile( Str, HashRef );
  my ( $class, $opts ) = $check->(@_);
  my %opts;

  my $configfile //= $opts->{configfile};

  if ( defined $configfile ) {
    my $hash = $class->get_config_from_file($configfile);
    no warnings 'uninitialized';
    croak "get_config_from_file($configfile) did not return a hash (got $hash)"
      unless reftype $hash eq 'HASH';
    %opts = ( %$hash, %$opts );
  }
  else {
    croak "new_with_config() expects configfile";
  }

  $class->new( \%opts );
}

sub get_config_from_file {
  #state $check = compile( Str, Object );
  my ( $class, $file ) = @_;

  my $fh = $class->get_read_fh($file);
  my $cleaned_txt;

  while (<$fh>) {
    chomp $_;
    if ( $_ =~ /\A#/ ) {
      say "ignoring comment in $file: $_";
    }
    elsif ( $_ =~ m/\A([\.\-\=\:\/\t\s\w\d]+)\Z/ ) {
      $cleaned_txt .= $1 . "\n";
    }
    elsif ( $_ =~ m/\A\s*\Z/ ) {
      say "skipping blank line in $file.";
    }
    else {
      croak "Bad data in $file: $_\n";
    }
  }

  return Load($cleaned_txt);
}

no Moose::Role;

1;
