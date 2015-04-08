#!/usr/bin/perl -w

##############################################################################
### This program parses Clinvar summary text File for SeqAnt usable flat file
##############################################################################

use 5.10.0;
use strict;
use warnings;

use Cwd;
use Carp;
use DBI;
use Getopt::Long;
use Pod::Usage;
use File::Spec;
use IO::Compress::Gzip qw/ $GzipError /;
use IO::Uncompress::Gunzip qw/ $GunzipError /;
use Try::Tiny;

##############################################################################
### Constants
##############################################################################

use constant FALSE => 0;
use constant TRUE  => 1;

use constant VERSION => '1.0.0';
use constant PROGRAM => eval { ( $0 =~ m/(\w+\.pl)$/ ) ? $1 : $0 };

###### Globals #########

my $cwd            = getcwd();
my %hCmdLineOption = ();
my $sHelpHeader    = "\nThis is " . PROGRAM . " version " . VERSION . "\n";
my ( $fpIN, $bDebug );
my @afields;

##############################################################################
### Main
##############################################################################

GetOptions( \%hCmdLineOption, 'infile|i=s', 'outfile|o=s', 'assembly|a=s',
  'verbose|v', 'debug', 'help', 'man' )
  or pod2usage(2);

if ( $hCmdLineOption{'debug'} ) {
  $hCmdLineOption{'infile'} = "";
  $bDebug = TRUE;
}

if ( $hCmdLineOption{'help'} || ( !defined $hCmdLineOption{'infile'} ) ) {
  pod2usage( -msg => $sHelpHeader, -exitval => 1 );
}
pod2usage( -exitval => 0, -verbose => 2 ) if $hCmdLineOption{'man'};

$bDebug = ( defined $hCmdLineOption{'debug'} ) ? TRUE : FALSE;
my $bVerbose  = ( defined $hCmdLineOption{'verbose'} ) ? TRUE : FALSE;
my $sInFile   = $hCmdLineOption{'infile'};
my $sOutFile  = $hCmdLineOption{'outfile'};
my $sAssembly = $hCmdLineOption{'assembly'};

( $bDebug || $bVerbose ) ? print STDERR "\n\t\tInput file\t: $sInFile\n" : undef;

## Download Clinvar database and create SQLite clinvar database

my $cmd =
  'wget ftp://ftp.ncbi.nlm.nih.gov/pub/clinvar/tab_delimited/variant_summary.txt.gz';
system($cmd) unless -e 'variant_summary.txt.gz';

my $dbh = DBI->connect(
  "dbi:SQLite:dbname=clinical.variation.db",
  "", "", { RaiseError => 1 },
) or die $DBI::errstr;

$dbh->do("DROP TABLE IF EXISTS clinvar");
$dbh->do(
  "CREATE TABLE clinvar(chrom TEXT, chromStart INT, chromEnd INT, name TEXT, ClinicalSignificance TEXT, ReviewStatus TEXT, PhenotypeID TEXT, Cytogenetic TEXT)"
);

$fpIN = IO::Uncompress::Gunzip->new($sInFile)
  or die "\tError : Cannot open $sInFile for reading .....\n";
open my $fpOUT, '>', $sOutFile
  or die "\tError : Cannot open $sOutFile for writing .....\n";

my $nX = 0;
my $nY = 0;
my ( $chr, $name );
my @asub;

my $sth = $dbh->prepare(
  qq{INSERT INTO clinvar(chrom,chromStart,chromEnd,name,ClinicalSignificance,ReviewStatus,PhenotypeID,Cytogenetic) VALUES( ?, ?, ?, ?, ?, ?, ?, ? )}
);

while ( my $line = $fpIN->getline ) {
  $line =~ s/\s+$//;

  if ( $nX == 0 ) {
    say $fpOUT
      "chrom\tchromStart\tchromEnd\tname\tClinicalSignificance\tReviewStatus\tPhenotypeID\tCytogenetic";
    $nY++;
  }

  else {
    my @afields = split( /\t/, $line );
    if ( $afields[12] eq $sAssembly ) {
      $chr = 'chr' . $afields[13];
      if ( $afields[6] != -1 ) {
        $name = 'rs' . $afields[6];
      }
      else {
        $name = 'NA';
      }
      if ( $chr and $afields[14] and $afields[15] ) {
        my @out_fields = (
          $chr,        $afields[14], $afields[15], $name,
          $afields[4], $afields[17], $afields[10], $afields[16]
        );
        say $fpOUT join( "\t", @out_fields );
        try {
          $sth->execute(@out_fields);
        }
        catch {
          warn "could not insert this data: @out_fields"
        }
      }
      else {
        if ($_) {
          warn "error processing line ($.): $_\n";
        }
        else {
          warn "error processing line ($.): undef\n";
        }
      }
    }
  }
  $nX++;
}
$dbh->disconnect();
# $cmd = 'rm $cwd/$sInFile';
# system($cmd);

##############################################################################
### POD Documentation
##############################################################################

__END__

=head1 NAME

processClinvar.pl - This program parses Clinvar summary text File for SeqAnt usable flat file.

=head1 SYNOPSIS
    process_clinvar.pl --i <input_file> --o <output_file> --a <assembly_name(GRCh37 or GRCh38)> [--v]
    parameters in [] are optional
    do NOT type the carets when specifying options

=head1 OPTIONS
    --i <input_file>        	= input file.

    --o <output_file>           = output file.

    --a <assembly_name>         = assembly name.

    --v                     	= generate runtime messages. Optional

=head1 DESCRIPTION

=head1 AUTHOR

Matthew Ezewudo
