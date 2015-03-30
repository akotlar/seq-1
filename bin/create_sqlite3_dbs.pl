#!/usr/bin/env perl
use 5.10.0;
use strict;
use warnings;
use DBI;
use YAML::XS qw( Dump );
use DDP;

my $dbh;
{
  $dbh = DBI->connect('dbi:SQLite:dbname=ucsc.sqlite3.db');
  local $/ = ";\n";
  $dbh->do($_) while <DATA>;
}

my $snp_data       = "snp141.txt";
my $knownGene_data = "knownGene.txt";
my $kgXref_data    = "kgXref_data";

# fill knownGene
{
  my $file = $knownGene_data;
  my $sth  = $dbh->prepare(
    qq{ INSERT INTO knownGene VALUES ( ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?) });
  open my $in_fh, "<", $knownGene_data;
  while (<$in_fh>) {
    say "$file: $.";
    chomp $_;
    my @line = split( /\t/, $_ );
    $sth->execute(@line);
  }
}

# fill kgXref
{
  my $file = $kgXref_data;
  my $sth =
    $dbh->prepare(qq{ INSERT INTO kgXref VALUES ( ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?) });
  open my $in_fh, "<", $file;
  while (<$in_fh>) {
    say "$file: $.";
    chomp $_;
    my @line = split( /\t/, $_ );
    $sth->execute(@line);
  }
}

# fill snp141
{
  my $file = $snp_data;
  my $sth  = $dbh->prepare(
    qq{ INSERT INTO snp141 VALUES ( ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?) }
  );
  open my $in_fh, "<", $file;
  while (<$in_fh>) {
    say "$file: $.";
    chomp $_;
    my @line = split( /\t/, $_ );
    $sth->execute(@line);
  }
}

__END__
BEGIN TRANSACTION;
DROP TABLE IF EXISTS knownGene;
DROP TABLE IF EXISTS kgXref;
DROP TABLE IF EXISTS snp141;
CREATE TABLE knownGene (
  name varchar(255) NOT NULL,
  chrom varchar(255) NOT NULL,
  strand char(1) NOT NULL,
  txStart integer NOT NULL,
  txEnd integer NOT NULL,
  cdsStart integer NOT NULL,
  cdsEnd integer NOT NULL,
  exonCount integer NOT NULL,
  exonStarts longblob NOT NULL,
  exonEnds longblob NOT NULL,
  proteinID varchar(40) NOT NULL,
  alignID varchar(255) NOT NULL
);
CREATE TABLE kgXref (
  kgID varchar(255) NOT NULL,
  mRNA varchar(255) NOT NULL,
  spID varchar(255) NOT NULL,
  spDisplayID varchar(255) NOT NULL,
  geneSymbol varchar(255) NOT NULL,
  refseq varchar(255) NOT NULL,
  protAcc varchar(255) NOT NULL,
  description longblob NOT NULL,
  rfamAcc varchar(255) NOT NULL,
  tRnaName varchar(255) NOT NULL,
  FOREIGN KEY(kgID) REFERENCES knownGene(name)
);
CREATE TABLE snp141 (
  bin smallint(5)  NOT NULL,
  chrom varchar(31) NOT NULL,
  chromStart int(10)  NOT NULL,
  chromEnd int(10)  NOT NULL,
  name varchar(15) NOT NULL,
  score smallint(5)  NOT NULL,
  strand text  NOT NULL,
  refNCBI blob NOT NULL,
  refUCSC blob NOT NULL,
  observed varchar(255) NOT NULL,
  molType text  NOT NULL,
  class text  NOT NULL,
  valid text  NOT NULL,
  avHet float NOT NULL,
  avHetSE float NOT NULL,
  func text  NOT NULL,
  locType text  NOT NULL,
  weight int(10)  NOT NULL,
  exceptions text  NOT NULL,
  submitterCount smallint(5)  NOT NULL,
  submitters longblob NOT NULL,
  alleleFreqCount smallint(5)  NOT NULL,
  alleles longblob NOT NULL,
  alleleNs longblob NOT NULL,
  alleleFreqs longblob NOT NULL,
  bitfields text  NOT NULL
);
COMMIT;
