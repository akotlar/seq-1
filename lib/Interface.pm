#!/usr/bin/env perl
use 5.10.0;

package Interface;

use File::Basename;

use Moose;
use Seq;
use MooseX::Types::Path::Tiny qw/Path File AbsFile AbsPath/;
use Moose::Util::TypeConstraints;
use Log::Any::Adapter;

use namespace::autoclean;

use DDP;

use YAML::XS qw/LoadFile/;
# use Try::Tiny;
use Path::Tiny;
with 'MooseX::Getopt::Usage';

#without this, Getopt won't konw how to handle AbsFile, AbsPath, and you'll get
#Invalid 'config_file' : File '/mnt/icebreaker/data/home/akotlar/my_projects/seq/1' does not exist
#but it won't understand AbsFile=> and AbsPath=> mappings directly, so below
#we use it's parental inference property 
#http://search.cpan.org/~ether/MooseX-Getopt-0.68/lib/MooseX/Getopt.pm
MooseX::Getopt::OptionTypeMap->add_option_type_to_map(
    'Path::Tiny' => '=s',
);
#not using Moose X types path tiny because it reads my file strings as "1" for some reason
has snpfile => (
  is        => 'rw',
  isa       => AbsFile,
  coerce => 1,
  #handles => {openInputFile => 'open'},
  required      => 1,
  handles => {
    snpfilePath => 'stringify',
  },
  writer => '_setSnpfile'
);

has out_file => (
  is          => 'ro',
  isa         => AbsPath,
  coerce      => 1,
  required    => 1,
  handles => {
    output_path => 'stringify',
  },
);

has config_file => (
  is          => 'ro',
  isa         => AbsFile,
  coerce      => 1,
  required    => 1,
  handles     => {
    configfilePath => 'stringify',
  },
);


enum file_types => [qw /snp_1 snp_2/];

has type => (
  is        => 'rw',
  isa       => 'file_types',
  #handles => {openInputFile => 'open'},
  required      => 0,
  default   => 'snp_2',
);

has overwrite => (
  is          => 'ro',
  isa         => 'Bool',
  default     => 0,
  required    => 0,
);

has ignore_unknown_chr => (
  metaclass   => 'Getopt',
  is          => 'ro',
  isa         => 'Bool',
  default     => 1,
  required    => 0,
  documentation =>
    qq{Ignore chromosomes not known to seqant, instead of crashing. Default 1}
);

has debug => (
  is          => 'ro',
  isa         => 'Num',
  default     => 0,
  required    => 0,
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
  is => 'ro',
  isa => 'ArrayRefFlex',
  required => 0,
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

has logPath => (
  is => 'rw',
  isa => 'Str',
  required => 0,
  init_arg => undef,
  lazy => 1,
  builder => '_buildLogPath',
);

sub _buildLogPath {
  my $self = shift;

  my $config_href = LoadFile($self->configfilePath)
    || die "ERROR: Cannot read YAML file at " . $self->configfilePath . ": $!\n";
  my $log_name = join '.', $self->output_path, 
    'annotation', $self->assembly, 'log';
  
  return path($self->output_path)->child($log_name)->stringify;
}

has assembly => (
  is => 'ro',
  isa => 'Str',
  required => 0,
  lazy => 1,
  builder => '_buildAssembly',
);

with 'Interface::Validator';

sub BUILD {
  my $self = shift;
  my $args = shift;
  
  $self->createLog;

  #$self->validateState; #exit if errors found via this Validator.pm method

  $self->_buildAnnotatorArguments;

  $self->_run;
}

#I wish for a neater way; but can't find method in MooseX::GetOpt to return just these arguments
sub _buildAnnotatorArguments {
  my $self = shift;

  for my $attr ( $self->meta->get_all_attributes ) {
    my $name = $attr->name;
    say "name is $name";
    if ( defined $self->{$name} ) {
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
  say "arguments are";
  p $self->_arguments;
  my $annotator = Seq->new( $self->_arguments );
  return $annotator->annotate_snpfile;
}

sub createLog {
  my $self = shift;
  
  say "writing log file here: " . $self->logPath if $self->debug;
  
  Log::Any::Adapter->set( 'File', $self->logPath );
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
