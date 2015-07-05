#!/usr/bin/env perl
# Name:           make_fake_genome.pl
# Date Created:   Wed Mar 11 10:22:55 2015
# Date Modified:  2015-03-16
# By:             TS Wingo
#
# Description: Prepare fake genomic data using single genes from each
#              chromosomes; write appropriate files to correct place in
#              the directory tree.
#
#   1. select a real coding gene from each chromosome, which will become the
#       entire chromsome in the fake genome
#   2. use 2bit file and twoBitToFa to get genomic sequence and write as a
#       gzipped file for each chromosome
#   3. shift genetic coordinates for each transcript to reflect the single
#       transcript as the entire test chromosome
#   4. write genomic transcripts after UCSC's knownGene table
#   5. write fake conservation scores - phyloP and phastCons
#   6. write fake snps that occur ~1% of the genome after UCSC's snp tables
#
#   TODO:
#     - haploinsufficiency - presently this is based on transcript ID but that
#       doesn't fold into the current framework well. Would rec changing to a
#       sparse type track (Alex)

use 5.10.0;
use strict;
use warnings;
use DBI;
use Data::Dumper;
use Carp qw/ croak /;
use Getopt::Long;
use File::Spec;
use File::Path qw/ make_path /;
use Path::Tiny;
use IO::File;
use IO::Compress::Gzip qw/ gzip $GzipError /;
use IO::Uncompress::Gunzip qw/ $GunzipError /;
use List::Util qw/ shuffle /;
use Pod::Usage;
use Scalar::Util qw/ looks_like_number /;
use YAML::XS qw/ LoadFile /;
use YAML::XS qw/ Dump /;

use DDP;

#
# variables
#
my ( $help, $out_ext, %snpfile_sites, $twobit_genome );

# defaults
my $location       = 'sandbox';
my $twobit2fa_prog = 'twoBitToFa';
my $config_file    = 'config/hg38_local.yml';
my $padding        = 0;
my $gene_count     = 1;

GetOptions(
  'c|config=s'        => \$config_file,
  'o|out=s'           => \$out_ext,
  'twoBitToFa_prog=s' => \$twobit2fa_prog,
  'twoBit_genome=s'   => \$twobit_genome,
  'l|location=s'      => \$location,
  'p|padding=n'       => \$padding,
  'h|help'            => \$help,
  'g|gene_count=n'    => \$gene_count,
);

if ($help) {
  Pod::Usage::pod2usage(1);
  exit;
}

unless ( $config_file
  and $out_ext
  and $twobit2fa_prog
  and $twobit_genome
  and $location
  and $gene_count > 0 )
{
  Pod::Usage::pod2usage();
}

if ($padding) {
  croak "padding should be between 1-10000" unless $padding > 0 && $padding < 10000;
}
else {
  $padding = 0;
}

# read config file, setup names for genome and chrs
my $config_href = LoadFile($config_file) || croak "cannot load $config_file: $!";

my $genome    = $config_href->{genome_name};
my $chrs_aref = $config_href->{genome_chrs};

unless ( $genome and $chrs_aref ) {
  say "cannot determine genome and/or chromosomes of genome from: $config_file";
  exit(1);
}

# choose gene and snp track names
my ( $gene_track_name, $snp_track_name );
for my $track ( @{ $config_href->{sparse_tracks} } ) {
  if ( $track->{type} eq 'gene' ) {
    $gene_track_name = $track->{name};
  }
  elsif ( $track->{type} eq 'snp' ) {
    $snp_track_name = $track->{name};
  }
  last if ( $gene_track_name && $snp_track_name );
}

unless ( $gene_track_name and $snp_track_name ) {
  say "cannot determine gene and snp track names from: $config_file";
  exit(1);
}

# setup UCSC connection
my $dsn = "DBI:mysql:host=genome-mysql.cse.ucsc.edu;database=$genome";
my $dbh = DBI->connect( $dsn, "genome", "" ) or croak "cannot connect to $dsn";

# change dir to directory where we'll download data
chdir $location
  or path($location)->mkpath and chdir $location
  or croak "cannot change into $location";

# get abs path to 2bit file
#   going to assume twoBitToFa is in path
unless ( File::Spec->file_name_is_absolute($twobit_genome) ) {
  my ( $vol, $dir, $file ) = File::Spec->splitpath($twobit_genome);
  $twobit_genome = File::Spec->rel2abs( $dir, $file );
}

# make dirs
my %out_dirs = (
  bed       => "$genome/test_files",
  snpfile   => "$genome/test_files",
  raw       => "$genome/raw",
  seq       => "$genome/raw/seq",
  snp       => "$genome/raw/snp",
  clinvar   => "$genome/raw/snp",
  gene      => "$genome/raw/gene",
  phyloP    => "$genome/raw/phyloP",
  phastCons => "$genome/raw/phastCons",
  haploIns  => "$genome/raw/haploInsufficiency"
);

%out_dirs =
  map { $_ => File::Spec->rel2abs( File::Spec->canonpath( $out_dirs{$_} ) ) }
  keys %out_dirs;
map { path( $out_dirs{$_} )->mkpath } keys %out_dirs;

# make files
my %out_files = (
  bed       => "$out_ext.bed.gz",
  snpfile   => "$out_ext.snp.gz",
  gene      => "$gene_track_name.txt.gz",
  phyloP    => 'phyloP.txt.gz',
  phastCons => 'phastCons.txt.gz',
  snp       => "$snp_track_name.txt.gz",
  clinvar   => 'clinvar.txt.gz',
  haploIns  => 'haploIns.txt.gz'
);
%out_files =
  map { $_ => File::Spec->catfile( $out_dirs{$_}, $out_files{$_} ) }
  keys %out_files;

# open file handles
my %out_fhs =
  map { $_ => IO::Compress::Gzip->new( $out_files{$_} ) } keys %out_files;

my ( %header, %found_chr, %chr_len, %chr_seq );

# create a hash of chr length offsets and initialize to zero
my %chr_length_offsets = map { $_ => 0 } @$chrs_aref;

for my $chr (@$chrs_aref) {
  my $sth = $dbh->prepare(
    qq{
    SELECT *
    FROM $genome.knownGene
    LEFT JOIN $genome.kgXref
    ON $genome.kgXref.kgID = $genome.knownGene.name
    WHERE ($genome.knownGene.chrom = '$chr')
    AND ($genome.knownGene.cdsStart != $genome.knownGene.cdsEnd)
    LIMIT $gene_count
    }
  ) or croak $dbh->errstr;
  my $rc = $sth->execute() or croak $dbh->errstr;
  my @header = @{ $sth->{NAME} };
  %header = map { $header[$_] => $_ } ( 0 .. $#header ) unless %header;
  while ( my @row = $sth->fetchrow_array ) {
    my %data = map { $_ => $row[ $header{$_} ] } keys %header;
    p %data;
    if ( $data{cdsEnd} != $data{cdsStart} ) {

      # save in bed file (real coordinates)
      say { $out_fhs{bed} }
        join( "\t", $data{chrom}, $data{txStart}, $data{txEnd}, $data{name} );

      # get real sequence from 2bit file
      my $seq_sref =
        Get_fa_seq( $chr, ( $data{txStart} - $padding ), ( $data{txEnd} + $padding ) );

      # add new sequence to existing 'chromosome' sequence
      my $seq = $chr_seq{$chr};
      if ($seq) {
        ${ $chr_seq{$chr} } .= ${$seq_sref};
      }
      else {
        $chr_seq{$chr} = $seq_sref;
      }

      my @exon_starts = split( /\,/, $data{exonStarts} );
      my @exon_ends   = split( /\,/, $data{exonEnds} );
      my $txStart     = $data{txStart} - $padding;

      my ( @new_exon_ends, @new_exon_starts );
      for ( my $i = 0; $i < @exon_starts; $i++ ) {
        my $new_start = $chr_length_offsets{$chr} + $exon_starts[$i] - $txStart;
        push @new_exon_starts, $new_start;
        my $new_ends = $chr_length_offsets{$chr} + $exon_ends[$i] - $txStart;
        push @new_exon_ends, $new_ends;
      }

      for my $ele (qw/ txEnd txStart cdsStart cdsEnd /) {
        $data{$ele} -= $txStart;
        $data{$ele} += $chr_length_offsets{$chr};
      }
      $data{exonStarts} = join( ",", @new_exon_starts );
      $data{exonEnds}   = join( ",", @new_exon_ends );

      # save 0-index sequence
      push @{ $found_chr{ $data{chrom} } }, \%data;
      $chr_len{$chr} += $data{txEnd} - $data{txStart} + 2 * $padding;

      # check length of sequence is correct after processing
      croak "expected lengths to match"
        unless length ${ $chr_seq{$chr} }
        == $chr_length_offsets{$chr} + ( $data{txEnd} - $data{txStart} ) + 2 * $padding;
      $chr_length_offsets{$chr} += length ${ $chr_seq{$chr} };
    }
  }
}
# change into seq dir to write files
chdir $out_dirs{seq} || croak "cannot change dir $out_dirs{seq}\n";
Write_gz_seq( \%chr_seq );

# change to raw dir
chdir $out_dirs{raw} or croak "cannot change dir $out_dirs{raw}\n";

# print fake knownGene data
{
  say { $out_fhs{gene} } join( "\t", ( map { $_ } ( sort keys %header ) ) );
  for my $chr ( sort keys %found_chr ) {
    for my $ele ( @{ $found_chr{$chr} } ) {
      say { $out_fhs{gene} } join( "\t", map { $ele->{$_} } ( sort keys %header ) );
    }
  }
}

# print fake conservation data - aboult half of the bases will have scores
# TODO: kotlar: is $i + 1 correct? we are all 0 indexed and UCSC is 0 indexed as well?
# https://genome.ucsc.edu/FAQ/FAQtracks.html
for my $chr (@$chrs_aref) {
  for ( my $i = 0; $i < $chr_len{$chr}; $i++ ) {
    say { $out_fhs{phastCons} } join( "\t", $chr, ( $i + 1 ), rand(1) )
      if rand(1) > 0.5;
    say { $out_fhs{phyloP} } join( "\t", $chr, ( $i + 1 ), ( rand(60) - 30 ) )
      if rand(1) > 0.5;
  }
}

# print fake haploinsufficiency data - about 70% of genes have scores
# pretends we have genome-wide haploinsufficiency data @ snv resolution
# TODO: what to do about promoter sequences?
{
  for my $chr ( sort keys %found_chr ) {
    say "\n\nWe found the gene symbol: $chr"; # . $found_chr{$chr}->{geneSymbol} ."\n";

    #at the moment %founcchr{$chr} is a 1 length 1D array
    #but $chr_length{$chr} is a scalar
    for my $geneRecord ( @{ $found_chr{$chr} } ) {
      for ( my $i = 0; $i < $chr_len{$chr}; $i++ ) {
        say { $out_fhs{haploIns} } join( "\t", $chr, $i, rand(1) )
          if rand(1) > 0.25;
      }
    }
    # say {$out_fhs{haploIns}} join("\t", $found_chr{$chr}{geneSymbol}, rand(1) )
    #   if rand(1) > 0.25;
  }
}
# print fake snp data - about 1% of sites will be snps
# for human genome, create clinvar data, about 0.05% will be clinvar sites
#

# print header
my @snp_fields =
  qw/ chrom chromStart chromEnd name alleleFreqCount alleles alleleFreqs /;
say { $out_fhs{snp} } join( "\t", @snp_fields );
my @clinvar_fields =
  qw/ chrom chromStart chromEnd name ClinicalSignificance ReviewStatus PhenotypeID Cytogenetic/;
say { $out_fhs{clinvar} } join( "\t", @clinvar_fields );

my @alleles = qw( A C G T I D );
my %seen_snp_name;
for my $chr (@$chrs_aref) {
  for ( my $i = 0; $i < $chr_len{$chr}; $i++ ) {

    # the following is to _not_ build a snp_track if there's not known variants
    # for the genome assembly
    if ( rand(1) > 0.99 && $snp_track_name ) {

      #  I strongly suspect that the mysql tables are zero-index
      #  and I know that the ucsc browser is 1 indexed.
      my $ref_base = uc substr( ${ $chr_seq{$chr} }, $i, 1 );
      my $minor_allele;
      my $name = 'rs' . int( rand(1000000) );
      my @allele_freq;
      push @allele_freq, sprintf( "%0.2f", rand(1) );
      push @allele_freq, sprintf( "%0.2f", ( 1 - $allele_freq[0] ) );
      @allele_freq = sort { $b <=> $a } @allele_freq;
      my @allele_freq_counts = map { $_ * 1000 } @allele_freq;

      do {
        $name = 'rs' . int( rand(1000000) );
      } while ( exists $seen_snp_name{$name} );
      $seen_snp_name{$name}++;

      do {
        $minor_allele = uc $alleles[ int( rand($#alleles) ) ];
      } while ( $minor_allele eq $ref_base );

      my $prn_chr = ( rand(1) > 0.95 ) ? join( "_", $chr, 'alt' ) : $chr;

      say { $out_fhs{snp} } join(
        "\t",
        $prn_chr,
        $i,         # start
        ( $i + 1 ), # end
        $name,
        join( ",", @allele_freq_counts ),
        join( ",", $ref_base, $minor_allele ),
        join( ",", @allele_freq )
      );

      # choose site (with 'known' snp) for snpfile
      my $rel_pos = $i + 1;
      $snpfile_sites{"$chr:$rel_pos"} = join( ":", $ref_base, $minor_allele )
        if ( rand(1) > 0.50 && $prn_chr !~ m/alt/ );
    }
    # choose site for snpfile, the rationale here is to build a snpfile
    # without depending on if the organism has known variants
    elsif ( rand(1) > 0.995 ) {
      my $ref_base = uc substr( ${ $chr_seq{$chr} }, $i, 1 );
      my $minor_allele;
      do {
        $minor_allele = uc $alleles[ int( rand(3) ) ];
      } while ( $minor_allele eq $ref_base );
      my $rel_pos = $i + 1;
      $snpfile_sites{"$chr:$rel_pos"} = join( ":", $ref_base, $minor_allele );
    }

    if ( $genome =~ m/\Ahg/ ) {
      if ( rand(1) > 0.999 ) {
        my @sig       = qw(pathogenic benign);
        my @pheno     = qw(MedGen OMIM GeneReviews);
        my @reviews   = qw(single multiple);
        my @cytogenic = qw(p22 q11 q24);

        my $snpid;
        my $cyto = uc substr( $chr, 3 );

        do {
          $snpid = 'rs' . int( rand(1000000) );
        } while ( exists $seen_snp_name{$snpid} );
        $seen_snp_name{$snpid}++;

        my $sig_val   = uc $sig[ int( rand(1) ) ];
        my $pheno_val = uc $pheno[ int( rand(2) ) ];
        my $cyto_val  = uc $cytogenic[ int( rand(2) ) ];
        my $rev_val   = uc $reviews[ int( rand(1) ) ];
        say { $out_fhs{clinvar} } join(
          "\t",
          $chr,
          $i,         # start
          ( $i + 1 ), # end
          $snpid,
          $sig_val,
          $rev_val,
          $pheno_val,
          join( ".", $cyto, $cyto_val )
        );
      }
    }
  }
}

# this accomidates the unlikely but possible situation we don't have anything
# to put into the snpfile
Print_snpfile( $out_fhs{snpfile}, \%snpfile_sites, '10' ) if %snpfile_sites;

# the following just prints out ids who are homozygous for the minor allele;
# limitations:
#   - if the y chromsome is included having a polymorphic y chr will make them men
#   - every one who is non-referance is a homozygote carrier
sub Print_snpfile {
  my ( $fh, $snpfile_href, $ids ) = @_;

  my @ids = map { 'id_' . $_ } ( 0 .. $ids );
  my @header = qw/ Fragment Position Reference Type Alleles Allele_Counts /;

  # print header
  say {$fh} join( "\t", join( "\t", @header ), join( "\t\t", @ids ) );

  for my $site ( sort keys %$snpfile_href ) {
    my ( $chr,        $pos )          = split( /:/, $site );
    my ( $ref_allele, $minor_allele ) = split( /:/, $snpfile_href->{$site} );
    my $carriers = 0;
    while ( $carriers == 0 ) {
      $carriers = int( rand($#ids) );
    }
    my $minor_allele_count = 2 * $carriers;
    my $major_allele_count = ( 2 * scalar @ids ) - $minor_allele_count;

    # choose type
    my $type;
    if ( $minor_allele eq 'I' ) {
      $type = 'INS';
    }
    elsif ( $minor_allele eq 'D' ) {
      $type = 'DEL';
    }
    elsif ( $minor_allele =~ m/[ACTG]/ ) {
      $type = 'SNP';
    }
    # print out preamble
    my $prnt_str = join( "\t",
      $chr, $pos, $ref_allele, $type,
      join( ",", $ref_allele,         $minor_allele ),
      join( ",", $major_allele_count, $minor_allele_count ) );
    $prnt_str .= "\t";

    # determine who should be homozygote carrier
    my @shuffled_ids = shuffle @ids;
    my @carrier_ids  = @shuffled_ids[ 0 .. $carriers ];
    my @alleles      = ();
    for my $id (@ids) {
      if ( grep { /\A$id\Z/ } @carrier_ids ) {
        push @alleles, join( "\t", $minor_allele, '1' );
      }
      else {
        push @alleles, join( "\t", $ref_allele, '1' );
      }
    }

    # print out carrier stuff
    $prnt_str .= join( "\t", @alleles );
    say {$fh} $prnt_str;
  }
}

# returns scalar reference to sequence for region
sub Get_fa_seq {
  my ( $chr, $start, $end ) = @_;
  croak "error processing Get_gz_seq() arguments @_"
    unless $chr
    and $start
    and $end;

  # grab sequence
  my $fa_file = qq{$chr.fa};
  my $cmd     = qq{$twobit2fa_prog $twobit_genome:$chr:$start-$end $fa_file};
  system $cmd;

  # check we got sequence
  croak "error grabbing sequence with cmd:\n\t$cmd\n" unless ( -s $fa_file );

  # get length of sequence
  #   and gzip file
  my $seq = '';
  my $fa_fh = IO::File->new( $fa_file, 'r' );
  # my $gz_fh = IO::Compress::Gzip->new("$fa_file.gz")
  #   or croak "gzip failed: $GzipError\n";
  while (<$fa_fh>) {
    chomp $_;
    $seq .= $_ unless ( $_ =~ m/\A>/ );
    #say {$gz_fh} $_;
  }
  unlink $fa_file;
  return \$seq;
}

# change into seq dir to write files
chdir $out_dirs{seq} || croak "cannot change dir $out_dirs{seq}\n";

sub Write_gz_seq {
  my ($href) = @_;

  my $dir = path( $out_dirs{seq} );

  for my $chr ( keys %$href ) {
    my $file  = $dir->child("$chr.fa.gz")->absolute->stringify;
    my $gz_fh = IO::Compress::Gzip->new($file)
      or croak "gzip failed: $GzipError\n";
    say {$gz_fh} ${ $href->{$chr} };
  }
}

__END__

=head1 NAME

make_fake_genome - prepare a 'fake' whole genome for Seq package using a configuration
file

=head1 SYNOPSIS

make_fake_genome.pl
  --config <file>
  --location <path>
  --twoBitToFa_prog <path/to/twoBitToFa_binary>
  --twoBit_genome <path/to/2bit_genome>
  --out <output extension for snpfile and bedfile of actual genomic coordinates>
  [--pading <int>]


=head1 DESCRIPTION

C<annotate_snpfile.pl> takes a genome assembly from a configuration file (YAML format)
and creates a small 'whole genome' consisting of different chromosomes and one
coding gene per chromosome.

=head1 OPTIONS

=over 8

=item B<-c>, B<--config>

Config: A YAML genome assembly configuration file that specifies the various
tracks and data associated with the assembly. This is the same file that is also
used by the Seq Package to build the binary genome without any alteration.

=item B<-l>, B<--location>

Location: This is the base directory for the location of the binary index.

=item B<--twoBitToFa_prog>

twoBitToFa_prog: Full path to the Jim Kent's twoBitToFa binary.

=item B<--twoBit_genome>

twoBit_genome: Full path to the 2bit genome for your genome of interest.

=item B<-p>, B<--padding>

Padding: How much to pad the coding sites. Default = 0.

=item B<-o>, B<--out>

Out: output extension for snpfile and bedfile of actual genomic coordinates.

=item B<-h>, B<--help>

Help: Prints help message.

=back

=head1 AUTHOR

Thomas Wingo

=head1 SEE ALSO

Seq Package

=cut
