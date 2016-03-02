#!/usr/bin/env perl
use 5.10.0;

package Interface;

use File::Basename;

use Moose;
extends 'Seq';
use MooseX::Types::Path::Tiny qw/Path File AbsFile AbsPath/;
use Moose::Util::TypeConstraints;
use Log::Any::Adapter;

use namespace::autoclean;

use DDP;

use YAML::XS qw/LoadFile/;
use Path::Tiny;

use Getopt::Long::Descriptive;
with 'MooseX::Getopt::Usage', 'MooseX::Getopt::Usage::Role::Man',
  'Seq::Role::Message';

#without this, Getopt won't konw how to handle AbsFile, AbsPath, and you'll get
#Invalid 'config_file' : File '/mnt/icebreaker/data/home/akotlar/my_projects/seq/1' does not exist
#but it won't understand AbsFile=> and AbsPath=> mappings directly, so below
#we use it's parental inference property
#http://search.cpan.org/~ether/MooseX-Getopt-0.68/lib/MooseX/Getopt.pm
MooseX::Getopt::OptionTypeMap->add_option_type_to_map( 'Path::Tiny' => '=s', );

##########Parameters accepted from command line#################
has snpfile => (
  is     => 'rw',
  isa    => AbsFile,
  coerce => 1,
  #handles => {openInputFile => 'open'},
  required      => 1,
  handles       => { snpfilePath => 'stringify', },
  writer        => 'setSnpfile',
  metaclass     => 'Getopt',
  cmd_aliases   => [qw/input snp i/],
  documentation => qq{Input file path.},
);

has out_file => (
  is            => 'ro',
  isa           => AbsPath,
  coerce        => 1,
  required      => 1,
  handles       => { output_path => 'stringify', },
  metaclass     => 'Getopt',
  cmd_aliases   => [qw/out output/],
  documentation => qq{Where you want your output.},
);

has config_file => (
  is            => 'ro',
  isa           => AbsFile,
  coerce        => 1,
  required      => 1,
  handles       => { configfilePath => 'stringify', },
  metaclass     => 'Getopt',
  cmd_aliases   => [qw/config/],
  documentation => qq{Yaml config file path.},
);

has overwrite => (
  is            => 'ro',
  isa           => 'Bool',
  default       => 0,
  required      => 0,
  metaclass     => 'Getopt',
  documentation => qq{Overwrite existing output file.},
);

has debug => (
  is        => 'ro',
  isa       => 'Num',
  default   => 0,
  required  => 0,
  metaclass => 'Getopt',
);

subtype HashRefJson => as
  'HashRef'; #subtype 'HashRefJson', as 'HashRef', where { ref $_ eq 'HASH' };
coerce HashRefJson => from 'Str' => via { from_json $_ };
subtype ArrayRefJson => as 'ArrayRef';
coerce ArrayRefJson => from 'Str' => via { from_json $_ };

has messanger => (
  is            => 'rw',
  isa           => 'HashRefJson',
  coerce        => 1,
  required      => 0,
  metaclass     => 'Getopt',
  documentation => qq{Tell Seqant how to send messages to a plugged-in interface 
      (such as a web interface) }
);

has publisherAddress => (
  is            => 'ro',
  isa           => 'ArrayRefJson',
  coerce        => 1,
  required      => 0,
  metaclass     => 'Getopt',
  documentation => qq{Tell Seqant how to send messages to a plugged-in interface 
      (such as a web interface) }
);

has ignore_unknown_chr => (
  is            => 'ro',
  isa           => 'Bool',
  default       => 1,
  required      => 0,
  metaclass     => 'Getopt',
  documentation => qq{Don't quit if we find a non-reference chromosome (like ChrUn)}
);

##################Not set in command line######################

has _logPath => (
  metaclass => 'NoGetopt',     # do not attempt to capture this param
  is        => 'rw',
  isa       => 'Str',
  required  => 0,
  init_arg  => undef,
  lazy      => 1,
  builder   => '_buildLogPath',
);

sub _buildLogPath {
  my $self = shift;

  my $config_href = LoadFile( $self->configfilePath )
    || die "ERROR: Cannot read YAML file at " . $self->configfilePath . ": $!\n";

  return join '.', $self->output_path, 'annotation', $self->assembly, 'log';
}

#@public, but not passed by commandl ine
has assembly => (
  is        => 'ro',
  isa       => 'Str',
  required  => 0,
  init_arg  => undef,
  lazy      => 1,
  builder   => '_buildAssembly',
  metaclass => 'NoGetopt',      # do not attempt to capture this param
);

with 'Interface::Validator';

sub BUILD {
  my $self = shift;
  my $args = shift;

  $self->createLog;

  #exit if errors found via this Validator.pm method
  $self->validateState;
}

#I wish for a neater way; but can't find method in MooseX::GetOpt to return just these arguments
sub _buildAnnotatorArguments {
  my $self = shift;
  my %args;
  for my $attr ( $self->meta->get_all_attributes ) {
    my $name  = $attr->name;
    my $value = $attr->get_value($self);
    next unless $value;
    $args{$name} = $value;
  }

  return \%args;
}

sub createLog {
  my $self = shift;

  Log::Any::Adapter->set( 'File', $self->_logPath );
}

sub _buildAssembly {
  my $self = shift;

  my $config_href =
    LoadFile( $self->configfilePath )
    || $self->tee_logger( 'error',
    sprintf( "ERROR: Cannot read YAML file at %s", $self->configfilePath ) );

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
