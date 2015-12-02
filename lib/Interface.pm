#!/usr/bin/env perl
use 5.10.0;

package Interface;

use File::Basename;

use Moose;
use Seq;
use MooseX::Types::Path::Tiny qw/File AbsFile AbsPath/;
use Moose::Util::TypeConstraints;
use Log::Any::Adapter;
with 'MooseX::Getopt::Usage';
with 'MooseX::Getopt::Usage::Role::Man';

use lib './lib';
use Seq;

use namespace::autoclean;

use DDP;

use YAML::XS;
# use Try::Tiny;
use Path::Tiny;

use Carp qw(cluck confess);
use Cwd 'abs_path';

#not using Moose X types path tiny because it reads my file strings as "1" for some reason
has snpfile => (
  metaclass => 'Getopt',
  is        => 'rw',
  isa       => AbsPath,
  coerce => 1,
  #handles => {openInputFile => 'open'},
  cmd_aliases   => [qw/ i s input in /],
  required      => 1,
  documentation => qq{Input file path. Required},
  handles => {
    snpfilePath => 'stringify',
  },
  writer => '_setSnpfile'
);

has out_file => (
  metaclass   => 'Getopt',
  is          => 'ro',
  isa         => AbsPath,
  coerce      => 1,
  required    => 1,
  cmd_aliases => [qw/ o output out /],
  handles => {
    output_path => 'stringify',
  },
  documentation =>
    qq{Output directory path. Required for non-prokaryotic annotations.}
);

has configfile => (
  metaclass   => 'Getopt',
  is          => 'ro',
  isa         => AbsFile,
  coerce      => 1,
  required    => 1,
  cmd_aliases => [qw/config c/],
  handles     => {
    configfilePath => 'stringify',
  },
  documentation =>
    qq{Pass a config file with all options in yaml format. Optional.}
);


enum file_types => [qw /snp_1 snp_2 vcf ped/];

has type => (
  metaclass => 'Getopt',
  is        => 'rw',
  isa       => 'file_types',
  #handles => {openInputFile => 'open'},
  cmd_aliases   => [qw/ t /],
  required      => 0,
  documentation => qq{Define the type of file}
);

has overwrite => (
  metaclass   => 'Getopt',
  is          => 'ro',
  isa         => 'Bool',
  cmd_aliases => 'f',
  default     => 0,
  required    => 0,
  documentation =>
    qq{Overwrite existing output files Optional. Default 0. Type: Bool}
);

has ignore_unknown_chr => (
  metaclass   => 'Getopt',
  is          => 'ro',
  isa         => 'Bool',
  cmd_aliases => 'i',
  default     => 1,
  required    => 0,
  documentation =>
    qq{Ignore chromosomes not known to seqant, instead of crashing. Default 1}
);

has debug => (
  metaclass   => 'Getopt',
  is          => 'ro',
  isa         => 'Num',
  cmd_aliases => 'd',
  default     => 0,
  required    => 0,
  documentation =>
    qq{Print debug information to screen during annotation. Default 0. Options: 1, 2 (2 prints all debug)}
);

subtype HashRefFlex => as 'HashRef';
coerce HashRefFlex => from 'Str' => via { from_json $_ };
subtype ArrayRefFlex => as 'ArrayRef';
coerce ArrayRefFlex => from 'Str' => via { from_json $_ };

# TODO: documetn 
has messanger => (
  metaclass   => 'Getopt',
  is => 'rw',
  isa => 'HashRefFlex',
  required => 0,
  documentation => 
    qq{Tell Seqant how to send messages to a plugged-in interface 
      (such as a web interface) }
);

has publisherAddress => (
  metaclass   => 'Getopt',
  is => 'ro',
  isa => 'ArrayRefFlex',
  required => 0,
  documentation => 
    qq{Tell Seqant where the listening server lives for the plugged-in interface.
     [server ip, port] }
);

has _arguments => (
  is       => 'rw',     #Todo: is validateState in builder cleaner than rw
  isa      => 'HashRef',
  traits   => ['Hash'],
  required => 1,
  init_arg => undef,
  default  => sub { {} },
  handles  => {
    setArg => 'set',
  }
);

has _logpath => (
  is => 'ro',
  isa => 'Str',
  required => 0,
  init_arg => undef,
  writer => '_setLogPath',
  reader => 'getLogPath',
);

has assembly => (
  is => 'ro',
  isa => 'Str',
  required => 0,
  lazy => 1,
  builder => '_buildAssembly',
);

sub getopt_usage_config {
  return (
    attr_sort      => sub { $_[0]->name cmp $_[1]->name },
    format         => "Usage: %c [OPTIONS]",
    headings       => 1,
    usage_sections => [
      'SYNOPSIS',      'USAGE',       'OPTIONS', 'VALID_FILES',
      'VALID_FORMATS', 'DESCRIPTION', 'EXAMPLES'
    ]
  );
}

with 'Interface::Validator';

sub BUILD {
  my $self = shift;
  my $args = shift;

  $self->createLog;

  $self->validateState; #exit if errors found via this Validator.pm method

  $self->_buildAnnotatorArguments;

  $self->_run;
}

#I wish for a neater way; but can't find method in MooseX::GetOpt to return just these arguments
sub _buildAnnotatorArguments {
  my $self = shift;

  for my $attr ( $self->meta->get_all_attributes ) {
    my $name = $attr->name;
    if ( defined $self->$name ) {
      $self->setArg($name => $self->$name);
    }
  }
  # if ( !$self->isProkaryotic ) {
  #   return { map { $_ => $self->$_; } qw(snpfile configfile out_file debug verbose) };
  # }
  # else {
  #   return { 'vcf' => $self->snpfile, 'gb' => $self->genBankAnnotation };
  # }
}

sub _run {
  my $self = shift;

  my $annotator = Seq->new( $self->_arguments );
  return $annotator->annotate_snpfile();
}

sub createLog {
  my $self = shift;

  my $config_href = LoadFile($self->configfilePath)
    || die "ERROR: Cannot read YAML file at " . $self->configfilePath . ": $!\n";
  my $log_name = join '.', $self->outfilePath, 
    'annotation', $self->assembly, 'log';
  
  $self->_setLogPath(path($self->outfilePath)->child($log_name)->stringify);
  
  say "writing log file here: " . $self->getLogPath if $self->debug;
  
  Log::Any::Adapter->set( 'File', $self->getLogPath );
}

sub _buildAssembly {
  my $self = shift;

  my $config_href = LoadFile($self->configfilePath)
    || die "ERROR: Cannot read YAML file at " . $self->configfilePath . ": $!\n";
  
  return $config_href->{genome_name};
}
__PACKAGE__->meta->make_immutable;

1;

=item messanger

Contains a hash reference (also accept json representation of hash) that 
tells Seqant how to send data to a plugged interface.

Example: {
      room: jobObj.userID,
      message: {
        publicID: jobObj.publicID,
        data: tData,
      },
    };
=cut


# sub _run {
#   my $self = shift;

#   if ( $self->isProkaryotic ) {
#     my $args = "--vcf " . $self->snpfile . " --gb " . $self->genBankAnnotation;

#     system( $self->_prokAnnotatorPath . " " . $args );
#   }
#   else {
#     my $aInstance = Seq->new( $self->_annotatorArgsHref );
#     $aInstance->annotate_snpfile();
#   }
# }

###optional

# has genBankAnnotation => (
#   metaclass   => 'Getopt',
#   is          => 'ro',
#   isa         => 'Str',
#   cmd_aliases => [qw/gb g gen_bank_annotation/],
#   required    => 0,
#   documentation =>
#     qq{GenBank Annotation file path. Required for prokaryotic annotations. Type Str.},
#   predicate => 'isProkaryotic'
# );


# has serverMode  => (
#   metaclass => 'Getopt',
#   is => 'ro',
#   isa => 'Bool',
#   cmd_aliases => 'qw/s server/',
#   required => 0,
#   default => 0,
#   documentation => qq{Enables persistent server mode}
# );

#private vars

# has _prokAnnotatorPath => (
#   is       => 'ro',
#   isa      => AbsFile,
#   required => 1,
#   init_arg => undef,
#   default  => sub {
#     return path( abs_path(__FILE__) )->absolute('/')
#       ->parent->parent->child('./bin/prokaryotic_annotator/vcf-annotator');
#   }
# );
