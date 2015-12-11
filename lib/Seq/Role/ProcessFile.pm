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
use List::MoreUtils qw(firstidx);
use namespace::autoclean;

requires 'output_path';
requires 'debug';

#requires get_write_bin_fh from Seq::Role::IO, can't formally requires it in a role
#requires tee_logger from Seq::Role::Message
with 'Seq::Role::IO', 'Seq::Role::Message';
# file_type defines the kind of file that is being annotated
#   - snp_1 => snpfile format: [ "Fragment", "Position", "Reference", "Minor_Allele"]
#   - snp_2 => snpfile format: ["Fragment", "Position", "Reference", "Alleles", "Allele_Counts", "Type"]
#   - vcf => placeholder
state $allowedTypes = [ 'snp_2', 'snp_1' ];
enum fileTypes => $allowedTypes;

has file_type => (
  is       => 'ro',
  isa      => 'fileTypes',
  required => 0,
  default  => '',
  writer   => 'setFileType'
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

has snpHeader => (
  traits => ['Array'],
  isa => 'ArrayRef',
  handles => {
    setSnpField => 'push',
    allSnpFieldIdx => 'elements',
  }
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

has _req_header_fields => (
  is => 'ro',
  isa => 'HashRef',
  traits => ['Hash'],
  lazy => 1,
  init_arg => undef,
  builder => '_build_headers',
  handles => {
    allReqFields => 'get',
  }
);

#API: The order here is the order of values returend for any consuming programs
#See: $self->proc_line
sub _build_headers {
  return {
    snp_1 => [qw/ Fragment Position Reference Type Minor_allele /],
    snp_2 => [qw/ Fragment Position Reference Type Alleles Allele_Counts /],
  };
}

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

sub checkHeader {
  my ( $self, $field_aref, $die_on_unknown ) = @_;
  $die_on_unknown = defined $die_on_unknown ? $die_on_unknown : 1;
  my $err;

  if($self->file_type) {
    $err = $self->_checkInvalid($field_aref, $self->file_type);
    $self->setHeader($field_aref);
  } else {
    for my $type (@$allowedTypes) {
      $err = $self->_checkInvalid($field_aref, $type);
      if(!$err) {
        $self->setFileType($type);
        $self->setHeader($field_aref);
        last;
      }
    }
    $err = "Error: " . $self->file_type . 
      "not supported. Please convert" if $err;
  }

  if($err) {
    if(defined $die_on_unknown) { $self->tee_logger( 'error', $err ); }
    else { $self->tee_logger( 'warn', $err ) };
    return; 
  }
  return 1;
}

# checks whether the first N fields, where N is the number of fields defined in
# $self->allReqFields, in the input file match the reqFields values
# order however in those first N fields doesn't matter
sub _checkInvalid {
  my ($self, $aRef, $type) = @_;

  my $reqFields = $self->allReqFields($type);
  my @inSlice = @$aRef[0 .. $#$reqFields];
  my $idx;
  for my $reqField (@$reqFields) {
    $idx = firstidx { $_ eq $reqField } @inSlice;
    if($idx == -1) {
      return "Input file header misformed. Coudln't find $reqField in first " 
        . @inSlice . ' fields.';
    }
  }
  return;
}

sub setHeader {
  my ($self, $aRef) = @_;

  my $idx;
  for my $field (@{$self->allReqFields($self->file_type) } ) {
    $idx = firstidx { $_ eq $field } @$aRef;
    say "First index for $field is $idx";
    $self->setSnpField($idx) unless $idx == -1;
  }
}

sub getSampleNamesIdx {
  my ($self, $fAref) = @_;
  my $strt = scalar @{$self->allReqFields($self->file_type) };

  # every other field column name is blank, holds genotype probability 
  # for preceeding column's sample;
  # don't just check for ne '', to avoid simple header issues
  my %data;

  for(my $i = $strt; $i <= $#$fAref; $i += 2) {
    $data{$fAref->[$i] } = $i;
  }
  return %data;
}

#presumes that file_type exists and has corresponding key in _req_header_fields
sub getSnpFields {
  my ( $self, $fAref ) = @_;

  return map {$fAref->[$_] } $self->allSnpFieldIdx;
}

=head2

B<_build_out_fh> - returns a filehandle and allow users to give us a directory or a
filepath, if directory use some sensible default

=cut

sub _build_out_fh {
  my $self = shift;

  if ( !$self->output_path ) {
    say "Did not find a file or directory path in Seq.pm _build_out_fh" if $self->debug;
    return \*STDOUT;
  }

  # can't use is_file or is_dir check before file made, unless it alraedy exists
  return $self->get_write_bin_fh( $self->output_path );
}

no Moose::Role;
1;
