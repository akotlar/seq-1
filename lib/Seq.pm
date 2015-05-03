use 5.10.0;
use strict;
use warnings;

package Seq;

# ABSTRACT: A class for kickstarting building or annotating things
# VERSION

use Moose 2;

use Carp qw/ croak /;
use namespace::autoclean;
use File::Spec;
use Text::CSV_XS;
use Seq::Annotate;

use DDP;

with 'Seq::Role::IO';

has snpfile => (
  is       => 'ro',
  isa      => 'Str',
  required => 1,
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

has debug => (
  is      => 'ro',
  isa     => 'Bool',
  default => 0,
);

has _out_fh => (
  is      => 'ro',
  lazy    => 1,
  builder => '_build_out_fh',
);

has _count_key => (
  is      => 'ro',
  lazy    => 1,
  default => 'count',
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
  K => [ 'G', 'T' ],
  M => [ 'A', 'C' ],
  R => [ 'A', 'G' ],
  S => [ 'C', 'G' ],
  W => [ 'A', 'T' ],
  Y => [ 'C', 'T' ],
  A => ['A'],
  C => ['C'],
  G => ['G'],
  T => ['T'],
  # the following indel codes are not technically IUPAC but part of the snpfile spec
  D => ['-'],
  E => ['-'],
  H => ['+'],
  N => [],
);

my $homozygote_regex = qr{[ACGTDI]+};
my $heterozygote_regex = qr{[KMRSWYEH]+};

sub _build_out_fh {
  my $self = shift;
  if ( $self->out_file ) {
    my $out_file = File::Spec->rel2abs( $self->out_file );
    # my $out_file = path( $self->out_file )->absolute->stringify;
    return $self->get_write_bin_fh($out_file);
  }
  else {
    return \*STDOUT;
  }
}

sub _get_annotator {
  my $self           = shift;
  my $abs_configfile = File::Spec->rel2abs( $self->configfile );
  my $abs_db_dir     = File::Spec->rel2abs( $self->db_dir );
  #my $abs_configfile = path( $self->configfile )->absolute;
  #my $abs_db_dir     = path( $self->db_dir )->absolute;

  # change to the root dir of the database
  chdir($abs_db_dir) || die "cannot change to $abs_db_dir: $!";

  return Seq::Annotate->new_with_config( { configfile => $abs_configfile } );
}

sub annotate_snpfile {
  my $self = shift;

  croak "specify a snpfile to annotate\n" unless $self->snpfile;

  say "about to load annotation data" if $self->debug;
  # $self->_logger->info("about to load annotation data");

  # setup
  my $abs_snpfile = File::Spec->rel2abs( $self->snpfile );
  #my $abs_snpfile = path( $self->snpfile )->absolute->stringify;
  my $snpfile_fh = $self->get_read_fh($abs_snpfile);
  my $annotator  = $self->_get_annotator;

  say "loaded annotation data" if $self->debug;
  # $self->_logger->info("loaded annotation data");

  # for writing data
  my $csv_writer = Text::CSV_XS->new(
    { binary => 1, auto_diag => 1, always_quote => 1, eol => "\n" } );

  # write header
  my @header = $annotator->all_header;
  push @header, 'heterozygotes_ids', 'homozygote_ids', 'chr', 'pos', 'type', 'alleles', 'allele_counts';
  $csv_writer->print( $self->_out_fh, \@header ) or $csv_writer->error_diag;

  say "about to process snp data\n";

  # process snpdata
  my ( %header, %ids, @sample_ids, $summary_href );
  while ( my $line = $snpfile_fh->getline ) 
  {

    # process snpfile
    chomp $line;
    my $clean_line = $self->clean_line($line);

    # skip lines that don't return any usable data
    next unless $clean_line;

    my @fields = split( /\t/, $clean_line );

    # for snpfile, define columns for expected header fields and ids
    if ( $. == 1 ) 
    {
      %header = map { $fields[$_] => $_ } ( 0 .. 5 );
      p %header if $self->debug;
      for my $i ( 6 .. $#fields ) {
        $ids{ $fields[$i] } = $i if ( $fields[$i] ne '' );
      }
      print "ids hash:\n";
      p %ids if $self->debug;

      @sample_ids = sort { $a <=> $b }  keys %ids; # to avoid calling keys on every _get_minor_allele_carriers call

      next;
    }

    # get basic information about variant
    my $chr           = $fields[ $header{Fragment} ];
    my $pos           = $fields[ $header{Position} ];
    my $ref_allele    = $fields[ $header{Reference} ];
    my $type          = $fields[ $header{Type} ];
    my $all_alleles   = $fields[ $header{Alleles} ];
    my $allele_counts = $fields[ $header{Allele_Counts} ];
    my $abs_pos       = $annotator->get_abs_pos( $chr, $pos );

    # get carrier ids for variant; returns hom_ids_href for use in statistics calculator later (hets currently ignored)
    my ( $het_ids, $hom_ids, $hom_ids_href ) =
      $self->_get_minor_allele_carriers( \@fields, \%ids, \@sample_ids, $ref_allele );

    if ( $self->debug ) 
    {
      say join " ", $chr, $pos, $ref_allele, $type, $all_alleles, $allele_counts,
        'abs_pos:', $abs_pos;
      say "het_ids:";
      p $het_ids;
      say "hom_ids";
      p $hom_ids;
    }

    if ( $type eq 'INS' or $type eq 'DEL' or $type eq 'SNP' ) 
    {
      my $method = lc 'set_' . $type . '_site';

      p $method if $self->debug;
      $self->$method( $abs_pos => [ $chr, $pos ] );

      # get annotation for snp site
      next unless $type eq 'SNP';
      for my $allele ( split( /,/, $all_alleles ) ) 
      {
        p $allele if $self->debug;
        next if $allele eq $ref_allele;
        my $record_href = $annotator->get_snp_annotation( $abs_pos, $allele );
        $record_href->{chr}               = $chr;
        $record_href->{pos}               = $pos;
        $record_href->{type}              = $type;
        $record_href->{alleles}           = $all_alleles;
        $record_href->{allele_counts}     = $allele_counts;
        $record_href->{heterozygotes_ids} = $het_ids || 'NA';
        $record_href->{homozygote_ids}    = $hom_ids || 'NA';
        
        $summary_href = $self->_summarize($record_href, $summary_href, \@sample_ids, $hom_ids_href);

        my @record;
        for my $attr (@header) 
        {
           if (ref $record_href->{$attr} eq 'ARRAY') {
             push @record, join ";", @{ $record_href->{$attr} };
           }
           else {
             push @record, $record_href->{$attr};
           }
         }

        if ( $self->debug ) {
          p $record_href;
          p @record;
        }
        $csv_writer->print( $self->_out_fh, \@record ) or $csv_writer->error_diag;
      }
    }
  }
  my @snp_sites = sort { $a <=> $b } $self->keys_snp_sites;
  my @del_sites = sort { $a <=> $b } $self->keys_del_sites;
  my @ins_sites = sort { $a <=> $b } $self->keys_ins_sites;

  p $summary_href if $self->debug;
  # TODO: decide how to return data or do we just print it out...
  #   - print conservation scores...
  return $summary_href; #we may want to consider returning the full experiment hash, in case we do interesting things.
}

sub _summarize 
{
  my ($self, $record_href, $summary_href, $sample_ids_aref, $hom_ids_href) = @_;

  my $count_key = $self->_count_key;
  my $site_type = $record_href->{type};
  my $annotation_code = $record_href->{genomic_annotation_code};

  foreach my $id (@$sample_ids_aref)
  {
    $summary_href->{$id}->{$site_type}->{$count_key} += 1;
    $summary_href->{$id}->{$site_type}->{$annotation_code}->{$count_key} += 1;
  }
  #run statistics code maybe, unless we wait for end to save function calls
  #statistics code may include compound phylop/phastcons scores for the sample, or just tr:tv
  #here we will use $hom_ids_href, and if needed we can add $het_ids_href
  
  return $summary_href; #not nec. to return anything, but makes clearer what program does
}

sub _get_minor_allele_carriers {
  my ( $self, $fields_aref, $ids_href, $id_names_aref, $ref_allele ) = @_;

  my ( $het_ids, $hom_ids, $hom_ids_href ) = ('','',{});

  for my $id ( @$id_names_aref ) 
  {
    my $id_geno = $fields_aref->[ $ids_href->{$id} ];
    my $id_prob = $fields_aref->[ $ids_href->{$id} + 1 ];

    # skip homozygote reference && N's
    next if ( $id_geno eq $ref_allele || $id_geno eq 'N' );

    # non-ref homozygotes - recall D and I are for insertions and deletions
    #   and they are not part of IUPAC but snpfile spec
    if ( $id_geno =~ m/$homozygote_regex/ )
    { 
      $hom_ids .= $id.':'.$id_geno.';'; #should be faster than join
      $hom_ids_href->{$id} = $id_geno; #needed for statistic calculator
    };
    #old, remove if above solution sufficies push @hom_ids, $id if ( $id_geno =~ m/[ACGTDI]+/ );

    # non-ref heterozygotes - recall E and H are for het insertions and deletions
    #   and they are not part of IUPAC but snpfile spec
    if ( $id_geno =~ m/$heterozygote_regex/ )
    { 
      $het_ids .= $id.':'.$id_geno.';';
    };
    #push @het_ids, $id if ( $id_geno =~ m/[KMRSWYEH]+/ );
  }
  #can remove if more performance needed; not sure how slow chop is, an alternative is substr, but that's prob slower
  chop($hom_ids); chop($het_ids);  

  return ($het_ids, $hom_ids, $hom_ids_href); #for now we do not use het_ids for anything
}

__PACKAGE__->meta->make_immutable;

1;
