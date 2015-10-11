use 5.10.0;
use strict;
use warnings;

package Seq;

# ABSTRACT: A class for kickstarting building or annotating things
# VERSION

=head1 DESCRIPTION

  @class B<Seq>
  #TODO: Check description
  From where all annotation originates

  @example

Used in: None

Extended by: None

=cut

our $VERSION = '0.001';

use Moose 2;
use Moose::Util::TypeConstraints;
use MooseX::Types::Path::Tiny qw/AbsFile AbsPath/;
use Path::Tiny;

use Carp qw/ croak /;
use Cpanel::JSON::XS;
use namespace::autoclean;
# use Redis;

use DDP;
use Data::Dump qw/ dump/;

use Seq::Annotate;

with 'Seq::Role::IO', 'MooX::Role::Logger';

enum fileTypes => [ 'snp_1', 'snp_2', 'vcf' ];

# file_type defines the kind of file that is being annotated
#   - snp_1 => snpfile format: [ "Fragment", "Position", "Reference" ]
#   - snp_2 => snpfile format: ["Fragment", "Position", "Reference", "Alleles", "Allele_Counts", "Type"]
#   - vcf => placeholder
has file_type => (
  is       => 'ro',
  isa      => 'fileTypes',
  required => 1,
);

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

has ignore_unknown_chr  => (
  is      => 'ro',
  isa     => 'Bool',
  default => 1,
);

has force => (
  is      => 'ro',
  isa     => 'Bool',
  default => 0,
);

has debug => (
  is      => 'ro',
  isa     => 'Bool',
  default => 0,
);

has messageChannelHref => (
  is        => 'ro',
  isa       => 'HashRef',
  traits    => ['Hash'],
  required  => 0,
  predicate => 'wants_to_publish_messages',
  handles   => { channelInfo => 'get' }
);

# vars that are not initialized at construction
has _message_publisher => (
  is       => 'ro',
  required => 0,
  lazy     => 1,
  init_arg => undef,
  builder  => '_build_message_publisher',
  handles  => { _publishMessage => 'publish' }
);

has _out_fh => (
  is       => 'ro',
  lazy     => 1,
  init_arg => undef,
  builder  => '_build_out_fh',
);

has _count_key => (
  is       => 'ro',
  isa      => 'Str',
  lazy     => 1,
  init_arg => undef,
  default  => 'count',
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

has header => (
  traits  => ['Array'],
  is      => 'ro',
  isa     => 'ArrayRef',
  handles => {
    all_header_attr => 'elements',
    add_header_attr => 'push',
  },
  default => sub { [] },
);

has _printed_header => (
  is      => 'rw',
  traits  => ['Bool'],
  isa     => 'Bool',
  default => 0,
  handles => { set_printed_header => 'set', },
);

my %site_2_set_method = (
  DEL          => 'set_del_site',
  INS          => 'set_ins_site',
  MULTIALLELIC => 'set_snp_site',
  SNP          => 'set_snp_site',
);

# the genotype codes below are based on the IUPAC ambiguity codes with the notable
#   exception of the indel codes that are specified in the snpfile specifications

my %het_genos = (
 K => [ 'G', 'T' ],
  M => [ 'A', 'C' ],
  R => [ 'A', 'G' ],
  S => [ 'C', 'G' ],
  W => [ 'A', 'T' ],
  Y => [ 'C', 'T' ],
);

my %hom_genos = (
  A => [ 'A', 'A' ],
  C => [ 'C', 'C' ],
  G => [ 'G', 'G' ],
  T => [ 'T', 'T' ],
);

my %hom_indel = (
  D => [ '-', '-' ],
  I => [ '+', '+' ],
);

my %het_indel = (
  E => ['-'],
  H => ['+'],
);

# my $redisHost = 'localhost';
# my $redisPort = '6379';

=head2 annotation_snpfile

B<annotate_snpfile> - annotates the snpfile that was supplied to the Seq object

=cut

sub annotate_snpfile {
  my $self = shift;

  $self->_logger->info("about to load annotation data");

  if ( $self->wants_to_publish_messages ) {
    $self->_publish_message("about to load annotation data");
  }

  my $annotator = Seq::Annotate->new_with_config(
    {
      configfile => $self->config_file_path,
      debug      => $self->debug,
      force      => $self->force,
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
  my @header = ( $annotator->all_header, 'heterozygotes_ids', 'homozygote_ids' );
  my $summary_href;

  # add header information to Seq class
  $self->add_header_attr($_) for @header;

  $self->_tee_logger( 'info', "Loaded assembly " . $annotator->genome_name );

  # variables
  my ( %header, %ids, @sample_ids, @all_annotations ) = ();
  my ( $last_chr, $chr_offset, $next_chr, $next_chr_offset, $chr_index ) =
    ( -9, -9, -9, -9, -9 );

  # let the annotation begin
  my $snpfile_fh = $self->get_read_fh( $self->snpfile_path );
  while ( my $line = $snpfile_fh->getline ) {
    chomp $line;

    # taint check the snpfile's data
    my $clean_line = $self->clean_line($line);

    # skip lines that don't return any usable data
    next unless $clean_line;

    my @fields = split( /\t/, $clean_line );

    # for snpfile, define columns for expected header fields and ids
    if ( !%header ) {
      if ( $. == 1 ) {
        my $transition_column;
        if ( $self->file_type eq 'snp_1' ) {
          $transition_column = 3;
        }
        if ( $self->file_type eq 'snp_2' ) {
          $transition_column = 5;
        }
        else {
          my $msg = sprintf("Error: unrecognzied file_type");
          $self->_tee_logger( 'error', $msg );
        }

        %header = map { $fields[$_] => $_ } ( 0 .. $transition_column );
        $self->_check_header( \%header );

        for my $i ( ( $transition_column + 1 ) .. $#fields ) {
          $ids{ $fields[$i] } = $i if ( $fields[$i] ne '' );
        }

        # save list of ids within the snpfile
        @sample_ids = sort( keys %ids );
        next;
      }
    }

    # process the snpfile line
    my ( $chr, $pos, $ref_allele, $type, $all_alleles, $allele_counts ) =
      $self->_proc_line( \%header, \@fields );

    my $abs_pos;

    # check that $chr is an allowable chromosome
    unless ( exists $chr_len_href->{$chr} ) {
      my $msg =
        sprintf( "Error: unrecognized chromosome in input: '%s', pos: %d", $chr, $pos );
      # decide if we plow through the error or if we stop
      if ( $self->ignore_unknown_chr ) {
        $self->_tee_logger( 'warn', $msg );
      }
      else {
        $self->_tee_logger( 'error', $msg );
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
        $self->_tee_logger( 'error', $msg );
      }
      $abs_pos = $chr_offset + $pos - 1;
    }

    if ( $abs_pos > $next_chr_offset ) {
      my $msg = "Error: $chr:$pos is beyond the end of $chr $next_chr_offset";
      $self->_tee_logger->( 'error', $msg );
    }

    # save the current chr for next iteration of the loop
    $last_chr = $chr;

    # get carrier ids for variant; returns hom_ids_href for use in statistics calculator
    #   later (hets currently ignored)
    my ( $het_ids, $hom_ids, $hom_ids_href ) =
      $self->_minor_allele_carriers( \@fields, \%ids, \@sample_ids, $ref_allele );

    if ( exists $site_2_set_method{$type} ) {

      # get annotation for snp site otherwise save the information
      # (i.e., for indels since we'll annotate those afterward)
      if ( $type eq 'SNP' || $type eq 'MULTIALLELIC' ) {

        for my $allele ( split( /,/, $all_alleles ) ) {
          next
            if ( $allele eq $ref_allele
            or exists $hom_indel{$allele}
            or exists $het_indel{$allele}
            or $allele eq '-' );

          say join "\t", "site", $abs_pos, $ref_allele, $type, $allele, $chr, $pos,
            $all_alleles, $allele_counts;

          my $record_href =
            $annotator->get_snp_annotation( $chr_index, $abs_pos, $ref_allele, $allele );

          $record_href->{chr}               = $chr;
          $record_href->{pos}               = $pos;
          $record_href->{type}              = $type;
          $record_href->{alleles}           = $all_alleles;
          $record_href->{allele_counts}     = $allele_counts;
          $record_href->{heterozygotes_ids} = $het_ids || 'NA';
          $record_href->{homozygote_ids}    = $hom_ids || 'NA';

          $self->_summarize( $record_href, $summary_href, \@sample_ids, $hom_ids_href );

          my @record;
          for my $attr (@header) {
            if ( ref $record_href->{$attr} eq 'ARRAY' ) {
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
          push @all_annotations, \@record;
          $self->inc_counter;
        }
      }
      else {
        my $method = $site_2_set_method{$type};
        $self->$method( $abs_pos => [ $chr, $pos, $all_alleles ] );
      }

      if ( $self->counter > 1000 ) {
        $self->_print_annotations( \@all_annotations, $self->headerr );
        @all_annotations = ();
        $self->reset_counter;
        if ( $self->wants_to_publish_messages ) {
          $self->_publish_message("finished annotating position $pos");
        }
      }
    }
    else {
      my $msg = sprintf( "Error: unrecognized variant type: '%s'", $type );
      $self->_tee_logger( 'error', $msg );
    }
  }

  # finished printing the final snp annotations
  if (@all_annotations) {
    $self->_print_annotations( \@all_annotations, $self->header );
  }

  # print deletion sites
  {
    my @del_annotations =
      $annotator->annotate_del_sites( \%chr_index, $self->del_sites() );
    $self->_print_annotations( \@del_annotations, $self->header );
  }

  # print insertion sites
  {
    my @ins_annoations =
      $annotator->annotate_ins_sites( \%chr_index, $self->ins_sites() );
    $self->_print_annotations( \@ins_annoations, $self->header );
  }

  p $summary_href if $self->debug;

  # TODO: decide on the final return value, at a minimum we need the sample-level summary
  #       we may want to consider returning the full experiment hash, in case we do
  #       interesting things.
  return $summary_href;
}

# sub _build_message_publisher {
#   my $self = shift;
#
#   return Redis->new( host => $redisHost, port => $redisPort );
# }

sub _proc_line {
  my ( $self, $header_href, $fields_aref ) = @_;

  if ( $self->file_type eq 'snp_1' ) {
    my $chr         = $fields_aref->[ $header_href->{Fragment} ];
    my $pos         = $fields_aref->[ $header_href->{Position} ];
    my $ref_allele  = $fields_aref->[ $header_href->{Reference} ];
    my $type        = $fields_aref->[ $header_href->{Type} ];
    my $all_alleles = $fields_aref->[ $header_href->{Minor_Allele} ];
    return ( $chr, $pos, $ref_allele, $type, $all_alleles, '' );
  }
  elsif ( $self->file_type eq 'snp_2' ) {
    my $chr           = $fields_aref->[ $header_href->{Fragment} ];
    my $pos           = $fields_aref->[ $header_href->{Position} ];
    my $ref_allele    = $fields_aref->[ $header_href->{Reference} ];
    my $type          = $fields_aref->[ $header_href->{Type} ];
    my $all_alleles   = $fields_aref->[ $header_href->{Alleles} ];
    my $allele_counts = $fields_aref->[ $header_href->{Allele_Counts} ];
    return ( $chr, $pos, $ref_allele, $type, $all_alleles, $allele_counts );
  }
  else {
    my $msg = sprintf( "Error: unknown file_type '%s'", $self->file_type );
    $self->_tee_logger( 'error', $msg );
  }
}

=head2

B<_build_out_fh> - returns a filehandle and allow users to give us a directory or a
filepath, if directory use some sensible default

=cut

sub _build_out_fh {
  my $self = shift;

  if ( !$self->has_out_file ) {
    say "Did not find a file or directory path in Seq.pm _build_out_fh" if $self->debug;
    return \*STDOUT;
  }

  #can't use is_file or is_dir check before file made, unless it alraedy exists
  return $self->get_write_bin_fh( $self->output_path );
}

sub _build_annotator {
  my $self = shift;

  my $annotator = Seq::Annotate->new_with_config(
    {
      configfile => $self->config_file_path,
      debug      => $self->debug,
      force      => $self->force,
    }
  );
  return $annotator;
}

sub _print_annotations {
  my ( $self, $annotations_aref, $header_aref ) = @_;

  # print header
  if ( !$self->_printed_header ) {
    say { $self->_out_fh } join "\t", @$header_aref;
    $self->set_printed_header;
  }

  # print entries
  for my $entry_aref (@$annotations_aref) {
    say { $self->_out_fh } join "\t", @$entry_aref;
  }
}

sub _tee_logger {
  my ( $self, $log_method, $msg ) = @_;

  if ( $self->wants_to_publish_messages ) {
    $self->_publish_message($msg);
  }
  $self->_logger->$log_method($msg);

  if ( $log_method eq 'error' ) {
    confess $msg . "\n";
  }
}

sub _publish_message {
  my ( $self, $message ) = @_;

  # TODO: check performance of the array merge benefit is indirection, cost may be too high?
  $self->publish( $self->channelInfo('messageChannel'),
    encode_json( { %{ $self->channelInfo('recordLocator') }, message => $message } ) );
}

sub _summarize {
  my ( $self, $record_href, $summary_href, $sample_ids_aref, $hom_ids_href ) = @_;

  my $count_key       = $self->_count_key;
  my $site_type       = $record_href->{type};
  my $annotation_code = $record_href->{genomic_annotation_code};

  foreach my $id (@$sample_ids_aref) {
    $summary_href->{$id}{$site_type}{$count_key} += 1;
    $summary_href->{$id}{$site_type}{$annotation_code}{$count_key} += 1;
  }

  # run statistics code maybe, unless we wait for end to save function calls
  # statistics code may include compound phylop/phastcons scores for the sample,
  # or just tr:tv here we will use $hom_ids_href, and if needed we can add
  # $het_ids_href

  return;
}

sub _minor_allele_carriers {
  my ( $self, $fields_aref, $ids_href, $id_names_aref, $ref_allele ) = @_;

  my ( @het_ids, @hom_ids, $het_ids_str, $hom_ids_str );

  for my $id (@$id_names_aref) {
    my $id_geno = $fields_aref->[ $ids_href->{$id} ];
    my $id_prob = $fields_aref->[ $ids_href->{$id} + 1 ];

    # skip homozygote reference && N's
    next if ( $id_geno eq $ref_allele || $id_geno eq 'N' );

    if ( exists $het_genos{$id_geno} ) {
      push @het_ids, $id;
    }
    elsif ( exists $hom_genos{$id_geno} ) {
      push @hom_ids, $id;
    }
    $het_ids_str = join ";", @het_ids;
    $hom_ids_str = join ";", @hom_ids;
  }

  # return ids for printing
  return ( $het_ids_str, $hom_ids_str, \@hom_ids );
}

sub _check_header {
  my ( $self, $header_href ) = @_;

  my ( @req_fields, %exp_header );
  my $req_field_count = 0;

  if ( $self->file_type eq 'snp_1' ) {
    @req_fields = qw/ Fragment Position Reference Allele Type /;
  }
  elsif ( $self->file_type eq 'snp_2' ) {
    @req_fields = qw/ Fragment Position Reference Alleles Allele_Counts Type /;
  }
  elsif ( $self->file_type eq 'vcf' ) {
    my $msg = "Error: 'vcf' file_type is not implemented";
    $self->_tee_logger( 'error', $msg );
  }

  # make temp hash for expected attributes
  for my $attr (@req_fields) {
    $exp_header{$attr} = 1;
  }

  for my $obs_attr ( keys %$header_href ) {
    if ( exists $exp_header{$obs_attr} ) {
      $req_field_count++;
    }
  }

  if ( $req_field_count != scalar @req_fields ) {
    my $req_fields_str = join ",", @req_fields;
    my $obs_fields_str = join ",", keys %$header_href;
    my $msg = sprintf( "Error: Expected header fields: '%s'\n\tBut found fields: %s\n",
      $req_fields_str, $obs_fields_str );
    say $self->_tee_logger( 'error', $msg );
  }
}

__PACKAGE__->meta->make_immutable;

1;
