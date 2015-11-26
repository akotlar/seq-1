## Interface Class
use 5.10.0;

package Interface::Validator;

use Moose::Role;
with 'MooseX::Getopt::Usage';
with 'MooseX::Getopt::Usage::Role::Man';
use namespace::autoclean;

use MooseX::Types::Path::Tiny qw/AbsFile AbsPath/;

use DDP;

use Path::Tiny;
use Cwd 'abs_path';

use YAML::XS;
use File::Spec;
use Carp qw(cluck confess);

with 'Seq::Role::ProcessFile';
has errorsAref => (
  is        => 'rw',
  isa       => 'ArrayRef',
  required  => 1,
  default   => sub { return [] },
  predicate => 'hasError'
);

# has serverConfigPath => (
#   is       => 'ro',
#   isa      => AbsPath,
#   init_arg => undef,
#   required => 1,
#   default  => sub {
#     return path( abs_path(__FILE__) )->absolute('/')
#       ->parent->parent->parent->child('./config/web');
#   }
# );


#when we switch to our own vcf converter
# has vcfConverterParth => (
#   is       => 'ro',
#   isa      => AbsFile,
#   init_arg => undef,
#   required => 1,
#   default  => sub {
#     return path( abs_path(__FILE__) )->child('./bin/Vcf2SeqAnt_SNP_4_1.pl');
#   }
# );

has vcfConverterParth => (
  is       => 'ro',
  isa      => AbsFile,
  init_arg => undef,
  required => 1,
  default  => sub {
    return path( abs_path(__FILE__) )->child('./bin/GenomeAnalysisTK.jar');
  }
);

has binaryPedConverterPath => (
  is       => 'ro',
  isa      => AbsFile,
  init_arg => undef,
  required => 1,
  default  => sub {
    return path( abs_path(__FILE__) )->child('./bin/linkage-go');
  }
);


# has _annotatorConfig => (
#   is        => 'ro',
#   isa       => 'HashRef',
#   traits    => ['Hash'],
#   handles   => { getConfig => 'get', configKeys => 'keys' },
#   lazy      => 1,
#   init_arg  => undef,
#   builder   => '_buildAnnotatorConfig',
#   predicate => 'hasAnnotatorConfig',
# );

# has _allowedAssembliesHref => (
#   is => 'ro',
#   isa => 'HashRef',
#   traits => ['Hash'],
#   handles => {allowedAssembly => 'exists', allAssemblies => 'keys'},
#   required => 1,
#   lazy    => 1,
#   init_arg => undef,
#   builder => '_buildAllowedAssemblies'
# );

# has _requiredSnpHeadersAref => (
#   is       => 'ro',
#   isa      => 'ArrayRef',
#   required => 1,
#   lazy     => 1,
#   init_arg => undef,
#   builder  => '_buildRequiredSnpHeaders'
# );

sub _buildAnnotatorConfig {
  my $self = shift;
  return YAML::XS::LoadFile(
    $self->serverConfigPath->child('annotator_config.yml')->stringify );
}

# sub _buildAllowedAssemblies
# {
#   my $self = shift;
#   #return map{ $_ => 1 } @{$self->getConfig('allowed_assemblies') };
# }

sub _buildRequiredSnpHeaders {
  my $self = shift;
  say "inside _buildRequiredSnpHeaders";
  p $self->getConfig('required_snp_headers');

  return $self->getConfig('required_snp_headers');
}

sub _validateConfig {
  my $self = shift;

  # Todo: prokaryotic genomes
  # if ( !( $self->isProkaryotic || $self->configfile ) ) {
  #   push @{ $self->errorsAref },
  #     "\nMust provide assembly (like hg38) or the path to the configfile.\n";
  # }
}

sub _validateOutput {
  my $self = shift;

  if ( !( $self->isProkaryotic || $self->out_file ) ) {
    push @{ $self->errorsAref },
      "\nMust provide assembly (like hg38) or the path to the configfile.\n";
  }

  #todo: it would be good to validate the parent of the output path, to make
  # sure that we can write to it.
}

sub validateState {
  my $self = shift;

  $self->_validateConfig();

  $self->_validateInputFile();

  say "Allowed assemblies are";
  #p $self->allAssemblies;

  #$self->_validateAssembly();

  if (
    scalar @{ $self->errorsAref }
    ) #if $erorrs, Global symobl requires explicit package error
  {
    $self->getopt_usage( exit => 10, err => join( "\n", @{ $self->errorsAref } ) );
  }
}

#check if assembly exists in annotation db
#@return void
# sub _validateAssembly
# {
#   my $self = shift;
#   my $validAssembly = 0;
#   if( $self->assembly)
#   {
#     if($self->allowedAssembly($self->assembly) ){ $validAssembly = 1; }
#   }
#   elsif( !$self->assembly )
#   {
#     my $assembly = YAML::XS::LoadFile( $self->configfile->stringify )->{genome_name};

#     if( $self->allowedAssembly($assembly) )
#     {
#       $validAssembly = 1;
#     }
#   }

#   if(!$validAssembly)
#   {
#     push @{ $self->errorsAref }, "\nThis assembly isn't allowed. Allowed are: ". join(", ", $self->allAssemblies) . "\n";
#   }
# }

sub _validateInputFile {
  my $self = shift;
  my ( $isSnpfile, $isVCFfile ) = ( 0, 0 );

  $isSnpfile = $self->_validSNP();
  $isVCFfile = $self->_validVCF();

  say "snpfile is ${\$self->snpfile}";
  if ( !$isSnpfile && !$isVCFfile ) {
    push @{ $self->errorsAref },
      "\nThe input file doesn't look like it's properly formatted. Please check our documentation for the expected format, and try again.\n";
  }

  if ( $self->isProkaryotic && !$isVCFfile ) {
    push @{ $self->errorsAref },
      "\nThe input file doesn't look like a valid vcf file, which is required for prokaryotic jobs.\n";
  }

  if ( !$self->isProkaryotic && $isVCFfile ) {
    system("mv ${\$self->snpfile} ${\$self->snpfile}.prenorm");
    system(
      "bcftools norm -c x -D ${\$self->snpfile}.prenorm
      | ${\$self->vcfConverterParth} -o ${\$self->snpfile}.norm"
    );

    $self->snpfile = $self->snpfile . '.norm';
  }
}

#-1 means file couldn't be opened, 0 is non-vcf, 1 is vcf
#todo: use vcftools to check headers
sub _validVCF {
  my $self = shift;

  my $fh;
  open( $fh, '<', $self->snpfile ) or return -1;

  while (<$fh>) {
    chomp;

    next if ( $_ =~ /^$/ ); #blank

    if ( index( $_, '##fileformat=VCF' ) != -1 ) {
      return 1;
    }

    return 0;
  }
}

#-1 means file couldn't be opened, 0 is non-snp, 1 is snp
sub _validSNP {
  say "Inside valid snp";
  my $self = shift;

  p $self->snpfile;
  #my $fh = $self->openInputFile or return -1;
  my $fh;
  open( $fh, '<', $self->snpfile ) or return -1;

  my @requiredHeaders = @{ $self->_requiredSnpHeadersAref };

  my $requiredNumColumns = scalar @requiredHeaders + 2
    ; #should move this to has=> #requiredHeaders, and 2 sample columns: 1st sample allele, 2nd sample allele probability

  while (<$fh>) {
    chomp;

    #should we allow blank lines? if so:  next if ($_ =~ /^$/); #blank
    my %row = map { $_ => 1; } split( "\t", lc($_) );

    if ( scalar keys %row < $requiredNumColumns ) {
      return 0;
    }

    for my $reqHeader (@requiredHeaders) {
      if ( !exists( $row{ lc($reqHeader) } ) ) #lc for a bit more flexibility
      {
        return 0;
      }
    }

    return 1;
  }
}

1;
