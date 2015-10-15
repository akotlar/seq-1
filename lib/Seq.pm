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

use Moose 2;
use MooseX::Types::Path::Tiny qw/AbsFile AbsPath/;
use Path::Tiny;

use Carp qw/ croak /;
use Cpanel::JSON::XS;
use DDP;
use namespace::autoclean;
# use Redis;

use Seq::Annotate;
use Seq::Statistics::StatisticsCalculator;

with 'Seq::Role::IO', 'MooX::Role::Logger';

has snpfile => (
  is       => 'ro',
  isa      => AbsFile,
  coerce   => 1,
  required => 1,
  handles  => { snpfile_path => 'stringify' }
);

has configfile => (
  is       => 'ro',
  isa      => AbsFile,
  required => 1,
  coerce   => 1,
  handles  => { configfile_path => 'stringify' }
);

has out_file => (
  is        => 'ro',
  isa       => AbsPath,
  coerce    => 1,
  required  => 0,
  predicate => 'has_out_file',
  handles   => { output_path => 'stringify' }
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

has messangerHref => (
  is        => 'ro',
  isa       => 'HashRef',
  traits    => ['Hash'],
  required  => 0,
  predicate => 'wants_to_publish_messages',
  handles   => { messanger => 'get' }
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

has count_key => (
  is       => 'ro',
  isa      => 'Str',
  lazy     => 1,
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
my $redisHost = 'genome.local';
my $redisPort = '6379';

has counter => (
  is => 'rw',
  traits => ['Counter'],
  isa => 'Num',
  default => 0,
  handles => {
    inc_counter => 'inc',
    dec_counter => 'dec',
    reset_counter => 'reset',
  },
);

has _printed_header => (
  is => 'rw',
  traits => ['Bool'],
  isa => 'Bool',
  default => 0,
  handles => { set_printed_header => 'set', },
);

my %site_2_set_method = (
  DEL => 'set_del_site',
  INS => 'set_ins_site',
  MULTIALLELIC => 'set_snp_site',
  SNP => 'set_snp_site',
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
=head2 annotation_snpfile

B<annotate_snpfile> - annotates the snpfile that was supplied to the Seq object

=cut

sub annotate_snpfile {
  my $self = shift;

  $self->_logger->info("loading Seqant database");

  if ( $self->wants_to_publish_messages ) {
    $self->_publish_message("loading Seqant database");
  }

  my $annotator = Seq::Annotate->new_with_config(
    {
      configfile => $self->configfile_path,
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

  my %summary;

  $self->_logger->info( "Loaded assembly " . $annotator->genome_name );

  if ( $self->wants_to_publish_messages ) {
    $self->_publish_message( "Loaded assembly " . $annotator->genome_name );
  }

  # attributes / header
  my @header = $annotator->all_header;
  push @header, (qw/ heterozygotes_ids homozygote_ids /);

  # variables
  my ( %header, %ids, @sample_ids, @all_annotations ) = ();
  my ( $last_chr, $chr_offset, $next_chr, $next_chr_offset, $chr_index ) =
    ( -9, -9, -9, -9, -9 );

  #if we want to publish messages, publish only ever so often
  #more efficient to declare for all instead of checking if we want to publish
  my $i        = 0;
  my $interval = 200;

  my $statisticsCalculator = StatisticsCalculator->new_with_config(
    assembly=>$annotator->genome_name,
    experimentType=>'genome'
  );
  # let the annotation begin
  my $snpfile_fh = $self->get_read_fh( $self->snpfile_path );
  READ: while ( my $line = $snpfile_fh->getline ) {
    chomp $line;

    # taint check the snpfile's data
    my $clean_line = $self->clean_line($line);

    # skip lines that don't return any usable data
    next READ unless $clean_line;

    my @fields = split( /\t/, $clean_line );

    # for snpfile, define columns for expected header fields and ids
    if ( !%header ) {
      if ( $. == 1 ) {
        %header = map { $fields[$_] => $_ } ( 0 .. 5 );
        for my $i ( 6 .. $#fields ) {
          $ids{ $fields[$i] } = $i if ( $fields[$i] ne '' );
        }
        # save list of ids within the snpfile
        @sample_ids = sort( keys %ids );
        next READ;
      }
      else {
        # exit if we've read the first line and didn't find the header
        my $err_msg = qq{ERROR: Could not read header from file: };
        $self->_logger->error( $err_msg . " " . $self->snpfile_path );
        croak $err_msg . " " . $self->snpfile_path;
      }
    }

    # get basic information about variant
    my $chr           = $fields[ $header{Fragment} ];
    my $pos           = $fields[ $header{Position} ];
    my $ref_allele    = $fields[ $header{Reference} ];
    my $type          = $fields[ $header{Type} ];
    my $all_alleles   = $fields[ $header{Alleles} ];
    my $allele_counts = $fields[ $header{Allele_Counts} ];
    my $abs_pos;

    # check that $chr is an allowable chromosome
    unless ( exists $chr_len_href->{$chr} ) {
      my $err_msg = sprintf("ERROR: unrecognized chromosome in input: '%s', pos: %d", 
        $chr, $pos);
      $self->_logger->error( $err_msg );
      if ( $self->force ) {
        next;
      }
      else {
        croak $err_msg . " " . $self->snpfile_path;
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
      # say join " ", $chr, $pos, $chr_offset, $next_chr, $next_chr_offset;
      unless ( defined $chr_offset and defined $chr_index ) {
        croak "unable to set 'chr_offset' or 'chr_index' for: $chr\n";
      }
      $abs_pos = $chr_offset + $pos - 1;
    }

    # TODO: should we next here too?
    if ( $abs_pos > $next_chr_offset ) {
      my $err_msg = qq{ERROR: $chr:$pos is beyond the end of $chr $next_chr_offset\n};
      $self->_logger->error($err_msg);
      croak $err_msg;
    }

    # save the current chr for next iteration of the loop
    $last_chr = $chr;

    # id_geno_href has {id=>genotype} for all minor allele carriers
    my ( $het_ids, $hom_ids, $id_geno_href ) =
      $self->_get_minor_allele_carriers( \@fields, \%ids, \@sample_ids, $ref_allele );

    # if ( $self->debug ) {
    #   say join " ", $chr, $pos, $ref_allele, $type, $all_alleles, $allele_counts,
    #     'abs_pos:', $abs_pos;
    #   say "het_ids:";
    #   p $het_ids;
    #   say "hom_ids";
    #   p $hom_ids;
    # }

    for my $id (keys %{$id_geno_href}) {
      $summary{$id}{$type}{$self->count_key} += 1 ;
    }
    
    if ( exists $site_2_set_method{$type} ) {
      my $method = $site_2_set_method{$type};

      $self->$method( $abs_pos => [ $chr, $pos ] );

      # get annotation for snp site
      next READ unless $type eq 'SNP' or 'MULTIALLELIC';

      ALLELE: for my $allele ( split( /,/, $all_alleles ) ) {
        next ALLELE if ( $allele eq $ref_allele 
            or exists $hom_indel{$allele}
            or exists $het_indel{$allele});
        my $record_href =
          $annotator->get_snp_annotation( $chr_index, $abs_pos, $ref_allele, $allele );

        $record_href->{chr}               = $chr;
        $record_href->{pos}               = $pos;
        $record_href->{type}              = $type;
        $record_href->{alleles}           = $all_alleles;
        $record_href->{allele_counts}     = $allele_counts;
        $record_href->{heterozygotes_ids} = $het_ids || 'NA';
        $record_href->{homozygote_ids}    = $hom_ids || 'NA';
        
        for my $id (keys %{$id_geno_href} ) {
          $summary{$id}{$type}{
            $record_href->{genomic_annotation_code}
          }{$self->count_key} += 1;
        }

        $statisticsCalculator->recordTransitionTransversion(
          $type, $record_href->{genomic_annotation_code}, $ref_allele, $id_geno_href
        );
        
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
          say "the id geno href is";
          p $record_href;
          say "the record array is";
          p @record;
          say "the id geno href has";
          p $id_geno_href;
          say "the site type";
          p $record_href->{type};
        }
        push @all_annotations, \@record;
        $self->inc_counter;
      }

    }
      
    if ($self->counter > 500) {
      $self->_print_annotations( \@all_annotations, \@header );
      @all_annotations = ( );
      $self->reset_counter;
    }

    if ( $i == $interval ) {
      $i = 0;
      if ( $self->wants_to_publish_messages ) {
        $self->_publish_message("annotated $chr:$pos");
      }
    }
    ++$i;
  }

  # finished printing the final annotations
  if (@all_annotations) {
    $self->_print_annotations( \@all_annotations, \@header );
  }

  $statisticsCalculator->calculateStatistics(\%summary,'count');

  my @snp_sites = sort { $a <=> $b } $self->keys_snp_sites;
  my @del_sites = sort { $a <=> $b } $self->keys_del_sites;
  my @ins_sites = sort { $a <=> $b } $self->keys_ins_sites;

  # disabled: return $statisticsCalculator->leftHandMergeStatistics(\%summary);
  # something goes wrong, hash looks fine, but node.js doesn't receive, with errors 
  # in keymetrics : can't call property "annotaitonSummary" on undefined.
  return \%summary; 
}

sub _build_message_publisher {
  my $self = shift;

  return Redis->new( server=> "$redisHost:$redisPort" );
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

sub _get_annotator {
  my $self           = shift;
  my $abs_configfile = File::Spec->rel2abs( $self->configfile );
  my $abs_db_dir     = File::Spec->rel2abs( $self->db_dir );

  # change to the root dir of the database
  chdir($abs_db_dir) || die "cannot change to $abs_db_dir: $!";

  return Seq::Annotate->new_with_config( { configfile => $abs_configfile } );
}

sub _print_annotations {
  my ( $self, $annotations_aref, $header_aref ) = @_;

  # print header
  if (!$self->_printed_header) {
    say { $self->_out_fh } join "\t", @$header_aref;
    $self->set_printed_header;
  }

  # print entries
  for my $entry_aref (@$annotations_aref) {
    say { $self->_out_fh } join "\t", @$entry_aref;
  }
}

sub _publish_message {
  my ( $self, $message ) = @_;
  $self->messanger('message')->{data} = $message;

  # TODO: check performance of the array merge benefit is indirection, cost may be too high?
  $self->_publishMessage($self->messanger('channel'),
    encode_json($self->messangerHref) );
  #encode_json({$self->messangerHref }) 
}



sub _get_minor_allele_carriers {
  my ( $self, $fields_aref, $ids_href, $id_names_aref, $ref_allele ) = @_;

  my ( @het_ids, @hom_ids, $het_ids_str, $hom_ids_str, %id_geno_href );

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

    $id_geno_href{$id} = $id_geno;
  }

  # return ids for printing
  return ( $het_ids_str, $hom_ids_str, \%id_geno_href );
}

__PACKAGE__->meta->make_immutable;

1;
