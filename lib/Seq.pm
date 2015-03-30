use 5.10.0;
use strict;
use warnings;

package Seq;

# ABSTRACT: A class for kickstarting building or annotating things
# VERSION

use Moose 2;

use Carp qw/ croak /;
use namespace::autoclean;
use Path::Tiny;
use Text::CSV_XS;
use Seq::Annotate;

use DDP;

with 'Seq::Role::IO';

has snpfile => (
  is  => 'ro',
  isa => 'Str',
);

has configfile => (
  is       => 'ro',
  isa      => 'Str',
  required => 1,
);

has db_dir => (
  is       => 'ro',
  isa      => 'Str',
  required => 1,
);

has out_file => (
  is  => 'ro',
  isa => 'Str',
);

has _out_fh => (
  is      => 'ro',
  lazy    => 1,
  builder => '_build_out_fh',
);

has del_sites => (
  is      => 'rw',
  isa     => 'HashRef',
  default => sub { {} },
  traits  => ['Hash'],
  handles => {
    set_del_site     => 'set',
    get_del_site     => 'get',
    keys_del_sites   => 'keys',
    kv_del_sites     => 'kv',
    has_no_del_sites => 'is_empty',
  },
);

has ins_sites => (
  is      => 'rw',
  isa     => 'HashRef',
  default => sub { {} },
  traits  => ['Hash'],
  handles => {
    set_ins_site     => 'set',
    get_ins_site     => 'get',
    keys_ins_sites   => 'keys',
    kv_ins_sites     => 'kv',
    has_no_ins_sites => 'is_empty',
  },
);

has snp_sites => (
  is      => 'rw',
  isa     => 'HashRef',
  default => sub { {} },
  traits  => ['Hash'],
  handles => {
    set_snp_site     => 'set',
    get_snp_site     => 'get',
    keys_snp_sites   => 'keys',
    kv_snp_sites     => 'kv',
    has_no_snp_sites => 'is_empty',
  },
);

has genes_annotated => (
  is      => 'rw',
  isa     => 'HashRef',
  default => sub { {} },
  traits  => ['Hash'],
  handles => {
    set_gene_ann    => 'set',
    get_gene_ann    => 'get',
    keys_gene_ann   => 'keys',
    has_no_gene_ann => 'is_empty',
  },
);

my @allowed_genotype_codes = [qw( A C G T K M R S W Y D E H N )];

# IPUAC ambiguity simplify representing genotypes
my %IUPAC_codes = (
  K => [qw( G T )],
  M => [qw( A C )],
  R => [qw( A G )],
  S => [qw( C G )],
  W => [qw( A T )],
  Y => [qw( C T )],
  A => [qw( A )],
  C => [qw( C )],
  G => [qw( G )],
  T => [qw( T )],
  # these indel codes are not technically IUPAC but part of the snpfile spec
  D => [qw( '-' )],
  E => [qw( '-' )],
  H => [qw( '+' )],
  N => [],
);

sub _build_out_fh {
  my $self = shift;
  if ( $self->out_file ) {
    my $out_file = path( $self->out_file )->absolute->stringify;
    return $self->get_write_bin_fh($out_file);
  }
  else {
    return \*STDOUT;
  }
}

sub _get_annotator {
  my $self           = shift;
  my $abs_configfile = path( $self->configfile )->absolute;
  my $abs_db_dir     = path( $self->db_dir )->absolute;

  # change to the root dir of the database
  chdir($abs_db_dir) || die "cannot change to $abs_db_dir: $!";

  return Seq::Annotate->new_with_config( { configfile => $abs_configfile } );
}

sub annotate_snpfile {
  my $self = shift;

  croak "specify a snpfile to annotate\n" unless $self->snpfile;

  # setup
  my $abs_snpfile = path( $self->snpfile )->absolute->stringify;
  my $snpfile_fh  = $self->get_read_fh($abs_snpfile);
  my $annotator   = $self->_get_annotator;

  # for writing data
  my $csv_writer = Text::CSV_XS->new(
    { binary => 1, auto_diag => 1, always_quote => 1, eol => "\n" } );

  # write header
  my @header = $annotator->all_header;
  $csv_writer->print( $self->_out_fh, \@header ) or $csv_writer->error_diag;

  # process snpdata
  my ( %header, %ids );
  while ( my $line = $snpfile_fh->getline ) {

    # process snpfile
    chomp $line;
    my $clean_line = $self->clean_line($line);

    # skip lines that don't return any usable data
    next unless $clean_line;

    my @fields = split( /\t/, $clean_line );

    if ( $. == 1 ) {
      %header = map { $fields[$_] => $_ } ( 0 .. 5 );
      %ids    = map { $fields[$_] => $_ } ( 6 .. $#fields );
      next;
    }

    # get basic information about variant
    my $chr           = $fields[ $header{Fragment} ];
    my $pos           = $fields[ $header{Position} ];
    my $ref_allele    = $fields[ $header{Reference} ];
    my $type          = $fields[ $header{Type} ];
    my $all_alleles   = $fields[ $header{Alleles} ];
    my $allele_counts = $fields[ $header{Allele_Counts} ];

    if ( $type eq 'INS' or $type eq 'DEL' or $type eq 'SNP' ) {
      my $method = lc 'set_' . $type . '_site';
      $self->$method( $annotator->get_abs_pos( $chr, $pos ) => [ $chr, $pos ] );
    }

    # get carrier ids for variant
    my @carriers = $self->_get_minor_allele_carriers( \@fields, \%ids, $ref_allele );

    # get annotation for snp sites
    next unless uc $type eq 'SNP';
    for my $allele ( split( /,/, $all_alleles ) ) {
      next if $allele eq $ref_allele;
      my $record_href = $annotator->get_snp_annotation( $chr, $pos, $allele );
      my @record = map { $record_href->{$_} } @header;
      $csv_writer->print( $self->_out_fh, \@record ) or $csv_writer->error_diag;
    }
  }
  my @snp_sites = sort { $a <=> $b } $self->keys_snp_sites;
  my @del_sites = sort { $a <=> $b } $self->keys_del_sites;
  my @ins_sites = sort { $a <=> $b } $self->keys_ins_sites;

  # TODO: decide how to return data or do we just print it out...
  return;
}

sub _get_minor_allele_carriers {
  my ( $self, $fields_aref, $ids_href, $ref_allele ) = @_;
  my @carriers;

  for my $id ( keys %$ids_href ) {
    my $id_geno = $fields_aref->[ $ids_href->{$id} ];
    my $id_prob = $fields_aref->[ $ids_href->{$id} + 1 ];

    push @carriers, $id if $id_geno ne $ref_allele && $id_geno ne 'N';
  }
  return \@carriers;
}

__PACKAGE__->meta->make_immutable;

1;
