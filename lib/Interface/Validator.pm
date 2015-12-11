## Interface Class
use 5.10.0;

package Interface::Validator;

use Moose::Role;
with 'MooseX::Getopt::Usage';
with 'MooseX::Getopt::Usage::Role::Man';
use namespace::autoclean;

use MooseX::Types::Path::Tiny qw/File AbsFile AbsPath AbsDir/;

use DDP;

use Path::Tiny;
use Cwd 'abs_path';

use YAML::XS;
use Archive::Extract;
use Try::Tiny;
use Carp qw(cluck confess);

with 'Seq::Role::ProcessFile', 'Seq::Role::IO', 'Seq::Role::Message';

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
    return path(which('plink') );
  },
  handles => {
    vcf2ped => 'stringify',
  }
);

has binaryPedConverterPath => (
  is       => 'ro',
  isa      => AbsFile,
  init_arg => undef,
  required => 1,
  default  => sub {
    return path( abs_path(__FILE__) )->child('./bin/linkage-go');
  }, 
  handles => {
    ped2snp => 'stringify',
  }
);

has twoBitDir => (
  is       => 'ro',
  isa      => AbsPath,
  init_arg => undef,
  required => 1,
  default  => sub {
    return path( abs_path(__FILE__) )->child('./twobit');
  }, 
);

has convertDir => (
  isa => AbsDir,
  is => 'ro',
  coerce => 1,
  init_arg => undef,
  required => 0,
  lazy => 1,
  default => '_buildConvertDir',
);

sub _buildConvertDir {
  my $self = shift;
  
  my $path = $self->out_file->parent->child('converted');
  $path->mkpath;

  return $path;
}

has inputFileBaseName => (
  isa => 'Str',
  is => 'ro',
  init_arg => undef,
  required => 0,
  default => sub {
    my $self = shift;
    return $self->snpfile->basename('.*');
  },
);

has convertFileBasePath => (
  isa => 'Str',
  is => 'ro',
  init_arg => undef,
  required => 0,
  lazy => 1,
  default => sub {
    my $self = shift;
    return $self->convertDir->child($self->inputFileBaseName)->stringify;
  }
);

sub validateState {
  my $self = shift;

  $self->_validateInputFile();

  if (
    scalar @{ $self->errorsAref }
    ) #if $erorrs, Global symobl requires explicit package error
  {
    $self->getopt_usage( exit => 10, err => join( "\n", @{ $self->errorsAref } ) );
  }
}

sub _validateInputFile {
  my $self = shift;

  unless($self->snpfile->if_file) {
    # for now log an error, later let people provide 
    $self->tee_logger('error', 'Snpfile must be file, got ' . $self->snpfilePath);
    return;
  }
  my $fh = $self->get_read_fh($self->snpfile);

  if(!$self->check_snp_header(<$fh>) ) {
    if(! $self->convertToPed) {
      if(!$self->convertToSnp) {
        $self->tee_logger('error', 
          'Conversion failed, see log @ '. $self->getLogPath);
      }
    }
  }
}

sub convertToPed {
  my ($self, $attempts) = @_;
 
  $attempts = $attempts || 0;

  if($attempts > 2) {
    $self->tee_logger('exit', 
      "User exited file conversion: $!. See log @ ". $self->getLogPath
    );
  }

  my $outPath = $self->convertFileBasePath;
  system($self->vcf2ped . " --vcf " . $self->snpfilePath . " --out $outPath");

  return if $? == 2;

  # user quit
  if ($? == 1) {
    $self->tee_logger('warn', "User exited file conversion: $!");
    sleep(5);
    return $self->convertVcf($attempts++);
  }

  $self->convertToSnp($outPath);
  return 1;
}

sub convertToSnp {
  my ($self, $convertFilesPath, $attempts) = @_;

  $attempts = $attempts || 0;

  my $infiles;

  unless ($convertFilesPath) {
    my $archive;
    $convertFilesPath = $self->convertFileBasePath;
    try {
      $archive = Archive::Extract->new($self->snpfilePath);
    } catch {
      #probably not an archive
      $self->tee_logger('warn', $_);

      #if it's not an archive, maybe we were given a base path or directory
      $infiles = $self->_findBinaryPlinkFiles($convertFilesPath);

      if(!$infiles) {
        $self->tee_logger('error', $self . " did not find valid input file(s)");
      }
    }

    try {
      $archive->extract($convertFilesPath);
    } catch {
       $self->tee_logger('error', "Extraction failed for $convertFilesPath");
    }

  }

  my $cFiles = $self->_findBinaryPlinkFiles($convertFilesPath) unless $infiles;

  my $outPath = path($convertFilesPath)->child('.snp')->stringify;

  my $twobit = $self->twoBitDir->child($self->assembly . '.*')->stringify;

  my @args = ($self->ped2snp, '-bed', $cFiles->bed, '-bim', $cFiles->bim, 
    '-fam', $$cFiles->fam, '-out', $outPath, '-two', $twobit);
  system(@args);

  return if $? == 2;

  # user quit
  if ($? == 1) {
    $self->tee_logger('warn', "User exited file conversion: $!");
    sleep(5);
    return $self->convertToSnp($convertFilesPath, $attempts++);
  }

  $self->_setSnpfile($outPath);
  return 1;
}

sub _findBinaryPlinkFiles {
  my ($self, $infilePath) = shift;

  my $bed = path($infilePath)->child('*.bed');
  my $bim = path($infilePath)->child('*.bim');
  my $fam = path($infilePath)->child('*.fam');

  if($bed->is_file && $bim->is_file && $fam->is_file) {
    return {
      bed => $bed->stringify,
      bim => $bim->stringify,
      fam => $bim->stringify,
    }
  } 
  $self->tee_logger('warn', 
    'Bed, bim, and/or fam don\'t exist at ' . $infilePath
  );
  return; 
}
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

# sub _buildAnnotatorConfig {
#   my $self = shift;
#   return YAML::XS::LoadFile(
#     $self->serverConfigPath->child('annotator_config.yml')->stringify );
# }

# sub _validateOutput {
#   my $self = shift;

#   if ( !( $self->isProkaryotic || $self->out_file ) ) {
#     push @{ $self->errorsAref },
#       "\nMust provide assembly (like hg38) or the path to the configfile.\n";
#   }

#   #todo: it would be good to validate the parent of the output path, to make
#   # sure that we can write to it.
# }

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

# sub _validateInputFile {
#   my $self = shift;
#   my ( $isSnpfile, $isVCFfile ) = ( 0, 0 );

#   $isSnpfile = $self->_validSNP();
#   $isVCFfile = $self->_validVCF();

#   say "snpfile is ${\$self->snpfile}";
#   if ( !$isSnpfile && !$isVCFfile ) {
#     push @{ $self->errorsAref },
#       "\nThe input file doesn't look like it's properly formatted. Please check our documentation for the expected format, and try again.\n";
#   }

#   if ( $self->isProkaryotic && !$isVCFfile ) {
#     push @{ $self->errorsAref },
#       "\nThe input file doesn't look like a valid vcf file, which is required for prokaryotic jobs.\n";
#   }

#   if ( !$self->isProkaryotic && $isVCFfile ) {
#     system("mv ${\$self->snpfile} ${\$self->snpfile}.prenorm");
#     system(
#       "bcftools norm -c x -D ${\$self->snpfile}.prenorm
#       | ${\$self->vcfConverterParth} -o ${\$self->snpfile}.norm"
#     );

#     $self->snpfile = $self->snpfile . '.norm';
#   }
# }

# #-1 means file couldn't be opened, 0 is non-vcf, 1 is vcf
# #todo: use vcftools to check headers
# sub _validVCF {
#   my $self = shift;

#   my $fh;
#   open( $fh, '<', $self->snpfile ) or return -1;

#   while (<$fh>) {
#     chomp;

#     next if ( $_ =~ /^$/ ); #blank

#     if ( index( $_, '##fileformat=VCF' ) != -1 ) {
#       return 1;
#     }

#     return 0;
#   }
# }

# #-1 means file couldn't be opened, 0 is non-snp, 1 is snp
# sub _validSNP {
#   say "Inside valid snp";
#   my $self = shift;

#   p $self->snpfile;
#   #my $fh = $self->openInputFile or return -1;
#   my $fh;
#   open( $fh, '<', $self->snpfile ) or return -1;

#   my @requiredHeaders = @{ $self->_requiredSnpHeadersAref };

#   my $requiredNumColumns = scalar @requiredHeaders + 2
#     ; #should move this to has=> #requiredHeaders, and 2 sample columns: 1st sample allele, 2nd sample allele probability

#   while (<$fh>) {
#     chomp;

#     #should we allow blank lines? if so:  next if ($_ =~ /^$/); #blank
#     my %row = map { $_ => 1; } split( "\t", lc($_) );

#     if ( scalar keys %row < $requiredNumColumns ) {
#       return 0;
#     }

#     for my $reqHeader (@requiredHeaders) {
#       if ( !exists( $row{ lc($reqHeader) } ) ) #lc for a bit more flexibility
#       {
#         return 0;
#       }
#     }

#     return 1;
#   }
# }

1;
