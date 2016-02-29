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
use Seq::Progress;

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
  is       => 'ro',
  isa      => AbsPath,
  coerce   => 1,
  required => 0,
  handles  => { output_path => 'stringify' }
);

has ignore_unknown_chr => (
  is      => 'ro',
  isa     => 'Bool',
  default => 1,
  lazy    => 1,
);

has overwrite => (
  is      => 'ro',
  isa     => 'Bool',
  default => 0,
  lazy    => 1,
);

has debug => (
  is      => 'ro',
  isa     => 'Int',
  default => 0,
  lazy    => 1,
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
  lazy => 1,
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
  lazy => 1,
);

has write_batch => (
  is      => 'ro',
  isa     => 'Int',
  default => 100000,
  lazy    => 1,
);

#come after all attributes to meet "requires '<attribute>'"
with 'Seq::Role::ProcessFile', 'Seq::Role::Genotypes', 'Seq::Role::Message';

=head2 annotation_snpfile

B<annotate_snpfile> - annotates the snpfile that was supplied to the Seq object

=cut

sub annotate_snpfile {
  my $self = shift;

  $self->tee_logger( 'info', 'Loading annotation data' );

  my $annotator = Seq::Annotate->new_with_config(
    {
      configfile       => $self->config_file_path,
      debug            => $self->debug,
      messanger        => $self->messanger,
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
  $self->add_header_attr(@header);

  $self->tee_logger( 'info', "Loaded assembly " . $annotator->genome_name );

  #a file slurper that is compression-aware
  $self->tee_logger( 'info', "Reading input file" );

  my $fileLines = $self->get_file_lines( $self->snpfile_path );

  $self->tee_logger( 'info',
    sprintf( "Finished reading input file, found %s lines", scalar @$fileLines ) );

  my $defPos = -9; #default value, indicating out of bounds or not set
  # variables
  my ( %ids, @sample_ids, @snp_annotations ) = ();
  my ( $last_chr, $chr_offset, $next_chr, $next_chr_offset, $chr_index ) =
    ( $defPos, $defPos, $defPos, $defPos, $defPos );

  # progress counters
  my ( $pubProg, $writeProg );

  if ( $self->hasPublisher ) {
    $pubProg = Seq::Progress->new(
      {
        progressBatch  => 200,
        fileLines      => scalar @$fileLines,
        progressAction => sub {
          $pubProg->recordProgress( $pubProg->progressCounter );
          $self->publishMessage( { progress => $pubProg->progressFraction } );
        },
      }
    );
  }

  $writeProg = Seq::Progress->new(
    {
      progressBatch  => $self->write_batch,
      progressAction => sub {
        $self->publishMessage( 'Writing ' . $self->write_batch . ' lines to disk' )
          if $self->hasPublisher;
        $self->print_annotations( \@snp_annotations );
        @snp_annotations = ();
      },
    }
  );

  my ( @fields, $abs_pos, $foundVarType );
  for my $line (@$fileLines) {
    #if we wish to save cycles, can move this to original position, below
    #many conditionals, and then upon completion, set progress(1).
    $pubProg->incProgressCounter if $pubProg;
    #expects chomped lines

    # taint check the snpfile's data
    @fields = $self->get_clean_fields($line);

    # skip lines that don't return any usable data
    next unless $#fields;
    # API: snp files contain column names in the first row
    # check that these match the expected, which is based on $self->file_type
    # then, get everything else
    if ( !%ids ) {
      $self->checkHeader( \@fields );

      %ids = $self->getSampleNamesIdx( \@fields );

      # save list of ids within the snpfile
      @sample_ids = sort( keys %ids );
      next;
    }
    # process the snpfile line
    my ( $chr, $pos, $ref_allele, $var_type, $all_allele_str, $allele_count ) =
      $self->getSnpFields( \@fields );

    # not checking for $allele_count for now, because it isn't in use
    next unless $chr && $pos && $ref_allele && $var_type && $all_allele_str;

    # get carrier ids for variant; returns hom_ids_href for use in statistics calculator
    #   later (hets currently ignored)
    my ( $het_ids, $hom_ids, $id_genos_href ) =
      $self->_minor_allele_carriers( \@fields, \%ids, \@sample_ids, $ref_allele );

    # check that $chr is an allowable chromosome
    # decide if we plow through the error or if we stop
    # if we allow plow through, don't write log, to avoid performance hit
    if ( !exists $chr_len_href->{$chr} ) {
      next if $self->ignore_unknown_chr;
      $self->tee_logger( 'error',
        sprintf( "Error: unrecognized chromosome: '%s', pos: %d", $chr, $pos ) );
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
        $next_chr        = $defPos;
        $next_chr_offset = $genome_len;
      }

      # check that we set the needed variables for determining position
      unless ( defined $chr_offset and defined $chr_index ) {
        $self->tee_logger( 'error',
          "Error: Couldn't set 'chr_offset' or 'chr_index' for: $chr" );
      }
      $abs_pos = $chr_offset + $pos - 1;
    }

    if ( $abs_pos > $next_chr_offset ) {
      my $msg = "Error: $chr:$pos is beyond the end of $chr $next_chr_offset\n
        Did you choose the right reference assembly?";
      $self->tee_logger( 'error', $msg );
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
    if ( index( $var_type, 'SNP' ) > -1 ) {
      $foundVarType = 'SNP';
    }
    elsif ( index( $var_type, 'DEL' ) > -1 ) {
      $foundVarType = 'DEL';
    }
    elsif ( index( $var_type, 'INS' ) > -1 ) {
      $foundVarType = 'INS';
    }
    elsif ( index( $var_type, 'MULTIALLELIC' ) > -1 ) {
      $foundVarType = 'MULTIALLELIC';
    }
    else {
      $foundVarType = '';
    }

    if ($foundVarType) {
      my $record_href = $annotator->annotate(
        $chr,        $chr_index,    $pos,            $abs_pos,
        $ref_allele, $foundVarType, $all_allele_str, $allele_count,
        $het_ids,    $hom_ids,      $id_genos_href
      );
      if ( defined $record_href ) {
        if ( $self->debug > 1 ) {
          say 'In seq.pm record_href is';
          p $record_href;
        }
        push @snp_annotations, $record_href;
        $writeProg->incProgressCounter;
      }
    }
    elsif ( index( $var_type, 'MESS' ) == -1 && index( $var_type, 'LOW' ) == -1 ) {
      $self->tee_logger( 'warn', "Unrecognized variant type: $var_type" );
    }
  }

  # finished printing the final snp annotations
  if (@snp_annotations) {
    $self->tee_logger( 'info',
      sprintf( 'Writing remaining %s lines to disk', $writeProg->progressCounter ) );

    $self->print_annotations( \@snp_annotations );
    @snp_annotations = ();
  }

  $self->tee_logger( 'info', 'Summarizing statistics' );
  $annotator->summarizeStats;

  if ( $self->debug ) {
    say "The stats record after summarize is:";
    p $annotator->statsRecord;
  }

  $annotator->storeStats( $self->output_path );

  # TODO: decide on the final return value, at a minimum we need the sample-level summary
  #       we may want to consider returning the full experiment hash, in case we do
  #       interesting things.
  $self->tee_logger( 'info',
    sprintf( 'We found %s discordant_bases', $annotator->discordant_bases ) )
    if $annotator->discordant_bases;

  return $annotator->statsRecord;
}

# _minor_allele_carriers assumes the following spec for indels:
# Allele listed in sample column is one of D,E,I,H, or whatever single base
# codes are defined in Seq::Role::Genotypes
# However, the alleles listed in the Alleles column will not be these
# Instead, will indicate the type (- or +) followed by the number of bases created/removed rel.ref
# So the sample column gives us heterozygosity, while Alleles column gives us nucleotide composition
sub _minor_allele_carriers {
  my ( $self, $fields_aref, $ids_href, $id_names_aref, $ref_allele ) = @_;

  my %id_genos_href = ();
  my $het_ids_str   = '';
  my $hom_ids_str   = '';
  for my $id (@$id_names_aref) {
    my $id_geno = $fields_aref->[ $ids_href->{$id} ];
    # skip reference && N's && empty things
    next if ( !$id_geno || $id_geno eq $ref_allele || $id_geno eq 'N' );

    if ( $self->isHet($id_geno) ) {
      $het_ids_str .= "$id;";
    }
    elsif ( $self->isHomo($id_geno) ) {
      $hom_ids_str .= "$id;";
    }
    else {
      $self->tee_logger( 'warn', "$id_geno was not recognized, skipping" );
    }
    $id_genos_href{$id} = $id_geno;
  }
  if   ($hom_ids_str) { chop $hom_ids_str; }
  else                { $hom_ids_str = 'NA'; }
  if   ($het_ids_str) { chop $het_ids_str; }
  else                { $het_ids_str = 'NA'; }

  # return ids for printing
  return ( $het_ids_str, $hom_ids_str, \%id_genos_href );
}

__PACKAGE__->meta->make_immutable;

1;
