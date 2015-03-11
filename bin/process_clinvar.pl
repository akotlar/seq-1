#!/usr/bin/perl -w

##############################################################################
### This program parses Clinvar summary text File for SeqAnt usable flat file
##############################################################################

#use strict;
use Cwd;
use Carp;
use Getopt::Long;
use Pod::Usage;
use File::Spec;
use IO::Compress::Gzip qw($GzipError);
use IO::Uncompress::Gunzip qw($GunzipError);
use File::Temp qw/ tempfile /;
use FindBin qw($RealBin);
use DBI;

##############################################################################
### Constants
##############################################################################

use constant FALSE => 0;
use constant TRUE  => 1;

use constant VERSION => '1.0.0';
use constant PROGRAM => eval { ($0 =~ m/(\w+\.pl)$/) ? $1 : $0 };

##############################################################################
### Globals
##############################################################################
my $dbh = DBI->connect(          
    "dbi:SQLite:dbname=test.db", 
    "",                          
    "",                          
    { RaiseError => 1 },         
) or die $DBI::errstr;

$dbh->do("DROP TABLE IF EXISTS Clinvar");
$dbh->do("CREATE TABLE Clinvar(chrom TEXT, SNPID TEXT, chromStart INT, chromEnd INT, ClinicalSignificance TEXT, ReviewStatus TEXT, Origin TEXT, PhenotypeID TEXT, Cytogenic TEXT)");

my %hCmdLineOption = ();
my $sHelpHeader = "\nThis is ".PROGRAM." version ".VERSION."\n";

my ($sInFile, $sAssembly);
my $fpIN;
my @afields;

##############################################################################
### Main
##############################################################################

GetOptions( \%hCmdLineOption,
            'infile|i=s',
            'assembly|a=s',
            'verbose|v',
            'debug',
            'help',
            'man') or pod2usage(2);

if ($hCmdLineOption{'debug'}) {
	$hCmdLineOption{'infile'} = "";
	$bDebug = TRUE;
}

if ( $hCmdLineOption{'help'} || (! defined $hCmdLineOption{'infile'})) {
	pod2usage( -msg => $sHelpHeader, -exitval => 1);
}
pod2usage( -exitval => 0, -verbose => 2) if $hCmdLineOption{'man'};

$bDebug   = (defined $hCmdLineOption{'debug'}) ? TRUE : FALSE;
$bVerbose = (defined $hCmdLineOption{'verbose'}) ? TRUE : FALSE;

$sInFile = $hCmdLineOption{'infile'};

$sAssembly = $hCmdLineOption{'assembly'};

($bDebug || $bVerbose) ? print STDERR "\n\t\tInput file\t: $sInFile\n" : undef;

$fpIN = IO::Uncompress::Gunzip->new($sInFile) or die "\tError : Cannot open $sInFile for reading .....\n";


my $nX = 0;
my $nY = 0;
my ($chrs, $snpid);
my @asub;

while (<$fpIN>) {
	$_ =~ s/\s+$//;
	
	if ($nX == 0) {
		$nY++;
		}	
	
	else {
	      ($_, @afields) = split(/\t/, $_); 
	       if ($afields[11] eq $sAssembly) {
	           $chrs = 'chr'.$afields[12];
	           if ($afields[5] != -1) {
	               $snpid = 'rs'.$afields[5];
	              }
	           else {
	                 $snpid = 'NA';
	                }
	           @asub = split (/ /, $afields[16]);
	           $dbh->do("INSERT INTO Clinvar VALUES('$chrs', '$snpid', $afields[13],$afields[14],'$afields[4]','$asub[2]','$afields[10]','$afields[9]','$afields[15]' )");
	         }
	       }
	$nX++;
   }

$dbh->disconnect();
exit;

##############################################################################
### POD Documentation
##############################################################################

__END__

=head1 NAME

processClinvar.pl - This program parses Clinvar summary text File for SeqAnt usable flat file.

=head1 SYNOPSIS

    processClinvar.pl --i <input_file> --a <assembly_name> [--v]

    parameters in [] are optional
    do NOT type the carets when specifying options

=head1 OPTIONS

    --i <input_file>        	= input file.
    
    --a <assembly_name>         = assembly name.
	
    --v                     	= generate runtime messages. Optional

=head1 DESCRIPTION

=head1 DIAGNOSTICS

=head1 CONFIGURATION AND ENVIRONMENT

PERL5LIB environment variable should be set if Bio::Perl is in non-standard
location

=head1 DEPENDENCIES

None

=head1 INCOMPATIBILITIES

=head1 BUGS AND LIMITATIONS

There are no known bugs in this module. Please report problems to Amol Shetty
(mezewud@emory.edu). Patches are welcome.

=head1 AUTHOR

Matthew Ezewudo
            

