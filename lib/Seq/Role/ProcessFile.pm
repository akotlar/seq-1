package Seq::Role::ProcessFile;

our $VERSION = '0.001';

# ABSTRACT: A role for processing snp files
# VERSION

use 5.10.0;
use strict;
use warnings;

use Moose::Role;
use Moose::Util::TypeConstraints;
use File::Which qw(which);
use File::Basename;
use namespace::autoclean;

requires 'has_out_file';
requires 'output_path';
requires 'debug';

#requires get_write_bin_fh from Seq::Role::IO, can't formally requires it in a role
#requires tee_logger from Seq::Role::Message
with 'Seq::Role::IO', 'Seq::Role::Message';
# file_type defines the kind of file that is being annotated
#   - snp_1 => snpfile format: [ "Fragment", "Position", "Reference", "Minor_Allele"]
#   - snp_2 => snpfile format: ["Fragment", "Position", "Reference", "Alleles", "Allele_Counts", "Type"]
#   - vcf => placeholder
enum fileTypes => [ 'snp_1', 'snp_2', 'vcf' ];
has file_type => (
  is       => 'ro',
  isa      => 'fileTypes',
  required => 1,
  default  => 'snp_2',
);

has printed_header => (
  is      => 'rw',
  traits  => ['Bool'],
  isa     => 'Bool',
  default => 0,
  handles => { set_printed_header => 'set', },
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

has compress_extension => (
  is      => 'ro',
  lazy    => 1,
  default => '.tar.gz',
);

has _out_fh => (
  is       => 'ro',
  lazy     => 1,
  init_arg => undef,
  builder  => '_build_out_fh',
);
# _print_annotations takes an array reference of annotations and hash
# reference of header attributes and writes the header (if needed) to the
# output file and flattens the hash references for each entry and writes
# them to the output file
sub print_annotations {
  my ( $self, $annotations_aref, $header_aref ) = @_;

  # print header
  if ( !$self->printed_header ) {
    say { $self->_out_fh } join "\t", @$header_aref;
    $self->set_printed_header;
  }

  # cache header attributes
  my @header = $self->all_header_attr;

  # flatten entry hash references and print to file
  for my $entry_href (@$annotations_aref) {
    my @prt_record;
    for my $attr (@header) {
      if ( exists $entry_href->{$attr} ) {
        push @prt_record, $entry_href->{$attr};
      }
      else {
        push @prt_record, 'NA';
      }
    }
    say { $self->_out_fh } join "\t", @prt_record;
  }
}

sub compress_output {
  my $self = shift;

  $self->tee_logger( 'info', 'Compressing all output files' );

  if ( !-e $self->output_path ) {
    $self->tee_logger( 'warn', 'No output files to compress' );
    return;
  }

  # my($filename, $dirs) = fileparse($self->output_path);

  my $tar = which('tar') or $self->tee_logger( 'error', 'No tar program found' );
  my $pigz = which('pigz');
  if ($pigz) { $tar = "$tar --use-compress-program=$pigz"; } #-I $pigz

  my $outcome =
    system( "$tar -cf "
      . $self->output_path
      . $self->compress_extension . " "
      . $self->output_path
      . "*" );

  $self->tee_logger( 'warn', "Zipping failed with $?" ) unless $outcome == 0;
}

sub check_header {
  my ( $self, $header_href ) = @_;

  my ( @req_fields, %exp_header );
  my $req_field_count = 0;

  if ( $self->file_type eq 'snp_1' ) {
    @req_fields = qw/ Fragment Position Reference Minor_allele Type /;
  }
  elsif ( $self->file_type eq 'snp_2' ) {
    @req_fields = qw/ Fragment Position Reference Alleles Allele_Counts Type /;
  }
  elsif ( $self->file_type eq 'vcf' ) {
    my $msg = "Error: 'vcf' file_type is not implemented";
    $self->tee_logger( 'error', $msg );
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
    say $self->tee_logger( 'error', $msg );
  }
}

sub proc_line {
  my ( $self, $header_href, $fields_aref ) = @_;

  if ( $self->file_type eq 'snp_1' ) {
    my $chr         = $fields_aref->[ $header_href->{Fragment} ];
    my $pos         = $fields_aref->[ $header_href->{Position} ];
    my $ref_allele  = $fields_aref->[ $header_href->{Reference} ];
    my $var_type    = $fields_aref->[ $header_href->{Type} ];
    my $all_alleles = $fields_aref->[ $header_href->{Minor_allele} ];
    return ( $chr, $pos, $ref_allele, $var_type, $all_alleles, '' );
  }
  elsif ( $self->file_type eq 'snp_2' ) {
    my $chr           = $fields_aref->[ $header_href->{Fragment} ];
    my $pos           = $fields_aref->[ $header_href->{Position} ];
    my $ref_allele    = $fields_aref->[ $header_href->{Reference} ];
    my $var_type      = $fields_aref->[ $header_href->{Type} ];
    my $all_alleles   = $fields_aref->[ $header_href->{Alleles} ];
    my $allele_counts = $fields_aref->[ $header_href->{Allele_Counts} ];
    return ( $chr, $pos, $ref_allele, $var_type, $all_alleles, $allele_counts );
  }
  else {
    my $msg = sprintf( "Error: unknown file_type '%s'", $self->file_type );
    $self->tee_logger( 'error', $msg );
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

  # can't use is_file or is_dir check before file made, unless it alraedy exists
  return $self->get_write_bin_fh( $self->output_path );
}

no Moose::Role;
1;
