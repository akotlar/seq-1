use 5.10.0;
use strict;
use warnings;

package Seq;

our $VERSION = '0.001';

# ABSTRACT: A class for kickstarting building or annotating snpfiles
# VERSION

=head1 DESCRIPTION

  @class B<Seq>
  #TODO: Check description
  From where all annotation originates

  @example

Used in: None

Extended by: None

=cut

use Moose 2;
use MooseX::Types::Path::Tiny qw/AbsFile AbsPath/;
use Path::Tiny;
use IO::AIO;

use Carp qw/ croak /;
use Cpanel::JSON::XS;
use namespace::autoclean;

use DDP;

use Coro;

use Seq::Annotate;

has snpfile => (
  is       => 'ro',
  isa      => AbsFile,
  coerce   => 1,
  required => 1,
  handles  => { snpfile_path => 'stringify' }
);

has config_file => (
  is       => 'ro',
  isa      => AbsFile,
  required => 1,
  coerce   => 1,
  handles  => { config_file_path => 'stringify' }
);

has out_file => (
  is        => 'ro',
  isa       => AbsPath,
  coerce    => 1,
  required  => 0,
  predicate => 'has_out_file',
  handles   => { output_path => 'stringify' }
);

has ignore_unknown_chr => (
  is      => 'ro',
  isa     => 'Bool',
  default => 1,
);

has overwrite => (
  is      => 'ro',
  isa     => 'Bool',
  default => 0,
);

has debug => (
  is      => 'ro',
  isa     => 'Bool',
  default => 0,
);

has del_sites => (
  is       => 'rw',
  isa      => 'HashRef',
  init_arg => undef,
  default  => sub { {} },
  traits   => ['Hash'],
  handles  => {
    set_del_site     => 'set',
    get_del_site     => 'get',
    keys_del_sites   => 'keys',
    kv_del_sites     => 'kv',
    has_no_del_sites => 'is_empty',
  },
);

has ins_sites => (
  is       => 'rw',
  isa      => 'HashRef',
  init_arg => undef,
  default  => sub { {} },
  traits   => ['Hash'],
  handles  => {
    set_ins_site     => 'set',
    get_ins_site     => 'get',
    keys_ins_sites   => 'keys',
    kv_ins_sites     => 'kv',
    has_no_ins_sites => 'is_empty',
  },
);

has snp_sites => (
  is       => 'rw',
  isa      => 'HashRef',
  init_arg => undef,
  default  => sub { {} },
  traits   => ['Hash'],
  handles  => {
    set_snp_site     => 'set',
    get_snp_site     => 'get',
    keys_snp_sites   => 'keys',
    kv_snp_sites     => 'kv',
    has_no_snp_sites => 'is_empty',
  },
);

has genes_annotated => (
  is       => 'rw',
  isa      => 'HashRef',
  init_arg => undef,
  default  => sub { {} },
  traits   => ['Hash'],
  handles  => {
    set_gene_ann    => 'set',
    get_gene_ann    => 'get',
    keys_gene_ann   => 'keys',
    has_no_gene_ann => 'is_empty',
  },
);

has write_batch => (
  is      => 'ro',
  isa     => 'Int',
  default => 100000,
);

has counter => (
  is      => 'rw',
  traits  => ['Counter'],
  isa     => 'Num',
  default => 0,
  handles => {
    inc_counter   => 'inc',
    dec_counter   => 'dec',
    reset_counter => 'reset',
  },
);

my %site_2_set_method = (
  DEL          => 'set_del_site',
  INS          => 'set_ins_site',
  MULTIALLELIC => 'set_snp_site',
  SNP          => 'set_snp_site',
);

#come after all attributes to meet "requires '<attribute>'"
with 'Seq::Role::ProcessFile', 'Seq::Role::Genotypes', 'Seq::Role::Message';

=head2 annotation_snpfile

B<annotate_snpfile> - annotates the snpfile that was supplied to the Seq object

=cut

sub annotate_snpfile {
  my $self = shift;

  $self->tee_logger('info', 'about to load annotation data');

  my $annotator = Seq::Annotate->new_with_config(
    {
      configfile => $self->config_file_path,
      debug      => $self->debug,
      messanger  => $self->messanger,
      publisherAddress => $self->publisherAddress,
    }
  );

  # cache import hashes that are otherwise obtained via method calls
  #   - does this speed things up?
  #
  my $chrs_aref     = $annotator->genome_chrs;
  my %chr_index     = map { $chrs_aref->[$_] => $_ } ( 0 .. $#{$chrs_aref} );
  my $next_chr_href = $annotator->next_chr;
  my $chr_len_href  = $annotator->chr_len;
  my $genome_len    = $annotator->genome_length;
  my @header        = $annotator->all_header;

  # add header information to Seq class
  $self->add_header_attr($_) for @header;

  $self->tee_logger( 'info', "Loaded assembly " . $annotator->genome_name );

  # variables
  my ( %header, %ids, @sample_ids, @snp_annotations ) = ();
  my ( $last_chr, $chr_offset, $next_chr, $next_chr_offset, $chr_index ) =
    ( -9, -9, -9, -9, -9 );

  my $snpfile_fh = $self->get_read_fh($self->snpfile_path);
  while ( my $line = $snpfile_fh->getline ) {
    chomp $line;

    # taint check the snpfile's data
    my $clean_line = $self->clean_line($line);

    # skip lines that don't return any usable data
    next unless $clean_line;

    my @fields = split( /\t/, $clean_line );

    # for snpfile, define columns for expected header fields and ids
    if ( !%header ) {
      my $transition_column;
      if ( $self->file_type eq 'snp_1' ) {
        $transition_column = 3;
      }
      if ( $self->file_type eq 'snp_2' ) {
        $transition_column = 5;
      }
      else {
        my $msg = sprintf("Error: unrecognzied file_type");
        $self->tee_logger( 'error', $msg );
      }

      %header = map { $fields[$_] => $_ } ( 0 .. $transition_column );
      $self->check_header( \%header );

      for my $i ( ( $transition_column + 1 ) .. $#fields ) {
        $ids{ $fields[$i] } = $i if ( $fields[$i] ne '' );
      }

      # save list of ids within the snpfile
      @sample_ids = sort( keys %ids );
      next;
    }

    # process the snpfile line
    my ( $chr, $pos, $ref_allele, $var_type, $all_allele_str, $allele_count ) =
      $self->proc_line( \%header, \@fields );

    # get carrier ids for variant; returns hom_ids_href for use in statistics calculator
    #   later (hets currently ignored)
    my ( $het_ids, $hom_ids, $id_genos_href ) =
      $self->_minor_allele_carriers( \@fields, \%ids, \@sample_ids, $ref_allele );

    my $abs_pos;

    # check that $chr is an allowable chromosome
    unless ( exists $chr_len_href->{$chr} ) {
      my $msg =
        sprintf( "Error: unrecognized chromosome in input: '%s', pos: %d", $chr, $pos );
      # decide if we plow through the error or if we stop
      if ( $self->ignore_unknown_chr ) {
        $self->tee_logger( 'warn', $msg );
        next;
      }
      else {
        $self->tee_logger( 'error', $msg );
      }
    }

    # determine the absolute position of the base to annotate
    if ( $chr eq $last_chr ) {
      $abs_pos = $chr_offset + $pos - 1;
    }
    else {
      $chr_offset = $chr_len_href->{$chr};
      $chr_index  = $chr_index{$chr};
      $next_chr   = $next_chr_href->{$chr};
      if ( defined $next_chr ) {
        $next_chr_offset = $chr_len_href->{$next_chr};
      }
      else {
        $next_chr        = -9;
        $next_chr_offset = $genome_len;
      }

      # check that we set the needed variables for determining position
      unless ( defined $chr_offset and defined $chr_index ) {
        my $msg =
          sprintf( "Error: unable to set 'chr_offset' or 'chr_index' for: '%s'", $chr );
        $self->tee_logger( 'error', $msg );
      }
      $abs_pos = $chr_offset + $pos - 1;
    }

    if ( $abs_pos > $next_chr_offset ) {
      my $msg = "Error: $chr:$pos is beyond the end of $chr $next_chr_offset";
      $self->tee_logger->( 'error', $msg );
    }

    # save the current chr for next iteration of the loop
    $last_chr = $chr;

    # Annotate variant sites
    #   - SNP and MULTIALLELIC sites are annotated individually and added to an array
    #   - indels are saved in an array (because deletions might be 1 off or contiguous over
    #     any number of bases that cannot be determined a prior) and annotated en masse
    #     after all SNPs are annotated
    #   - NOTE: the way the annotations for INS sites now work (due to changes in the
    #     snpfile format, we could change their annotation to one off annotations like
    #     the SNPs
    if ( $var_type eq 'SNP' || $var_type eq 'MULTIALLELIC' ) {
      my $record_href = $annotator->annotate_snp_site(
        $chr,      $chr_index,      $pos,          $abs_pos, $ref_allele,
        $var_type, $all_allele_str, $allele_count, $het_ids, $hom_ids, $id_genos_href
      );
      if ( defined $record_href ) {
        push @snp_annotations, $record_href;
        $self->inc_counter;
      }
    }
    elsif ( $var_type eq 'INS' ) {
      my $record_href = $annotator->annotate_ins_site(
        $chr,      $chr_index,      $pos,          $abs_pos, $ref_allele,
        $var_type, $all_allele_str, $allele_count, $het_ids, $hom_ids, $id_genos_href
      );
      if ( defined $record_href ) {
        push @snp_annotations, $record_href;
        $self->inc_counter;
      }
    }
    elsif ( $var_type eq 'DEL' ) {
      # deletions are saved so they can be aggregated and annotated en block later
      $self->set_del_site( $abs_pos =>
          [ $chr, $pos, $ref_allele, $all_allele_str, $allele_count, $het_ids,
            $hom_ids, $id_genos_href ] );
    }
    elsif ($var_type ne 'MESS' && $var_type ne 'LOW') {
      my $msg = sprintf( "Error: unrecognized variant var_type: '%s'", $var_type );
      $self->tee_logger( 'warn', $msg );
    }

    # write data in batches
    if ( $self->counter > $self->write_batch ) {
      $self->print_annotations( \@snp_annotations, $self->header );
      @snp_annotations = ();
      $self->reset_counter; 
    }
    if($self->hasPublisher) {
      $self->publishMessage("annotated $chr:$pos");
    }
  }

  # finished printing the final snp annotations
  if (@snp_annotations) {
    $self->print_annotations( \@snp_annotations, $self->header );
    @snp_annotations = ();
  }

  # print deletion sites
  #   - indel annotations come back as an array reference of hash references
  #   - the print_annotations function flattens the hash reference and
  #     prints them in order
  unless ( $self->has_no_del_sites ) {
    my $del_annotations_aref =
      $annotator->annotate_del_sites( \%chr_index, $self->del_sites() );
    $self->print_annotations( $del_annotations_aref, $self->header );
  }

  $annotator->summarizeStats;

  if($self->debug) {
    say "The stats record after summarize is:";
    p $annotator->statsRecord;
  }

  $annotator->storeStats($self->output_path);

  # TODO: decide on the final return value, at a minimum we need the sample-level summary
  #       we may want to consider returning the full experiment hash, in case we do
  #       interesting things.
  return $annotator->statsRecord;
}

sub _minor_allele_carriers {
  my ( $self, $fields_aref, $ids_href, $id_names_aref, $ref_allele ) = @_;

  my %id_genos_href = ();
  my $het_ids_str = '';
  my $hom_ids_str = '';
  for my $id (@$id_names_aref) {
    my $id_geno = $fields_aref->[ $ids_href->{$id} ];
    my $id_prob = $fields_aref->[ $ids_href->{$id} + 1 ];

    # skip reference && N's
    next if ( $id_geno eq $ref_allele || $id_geno eq 'N' );

    if ( $self->isHomo($id_geno) ) {
      #push @hom_ids, $id;
      $hom_ids_str .= "$id;";
    } else {
      #push @het_ids, $id;
      $het_ids_str .= "$id;";
    }
    chop $hom_ids_str;
    chop $het_ids_str;
    $hom_ids_str = 'NA' unless $hom_ids_str;
    $het_ids_str = 'NA' unless $het_ids_str;
    # if (@het_ids) {
    #   $het_ids_str = join ";", @het_ids;
    # }
    # else {
    #   $het_ids_str = 'NA';
    # }
    # if (@hom_ids) {
    #   $hom_ids_str = join ";", @hom_ids;
    # }
    # else {
    #   $hom_ids_str = 'NA';
    # }
    $id_genos_href{$id} = $id_geno;
  }

  # return ids for printing
  return ( $het_ids_str, $hom_ids_str, \%id_genos_href);
}

__PACKAGE__->meta->make_immutable;

1;
