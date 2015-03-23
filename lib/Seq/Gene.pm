use 5.10.0;
use strict;
use warnings;

package Seq::Gene;
# ABSTRACT: Class for creating particular sites for a given gene / transcript
# VERSION

use Moose 2;

use Carp qw/ confess /;
use namespace::autoclean;

use Seq::GeneSite;

# has features of a gene and will run through the sequence
# build features will be implmented in Seq::Build::Gene that can build GeneSite
# objects
# would be useful to extend to have capcity to build peptides

my $splice_site_length = 6;

has genome_track => (
  is       => 'ro',
  required => 1,
  handles  => [ 'get_abs_pos', 'get_base', ],
);

has chr              => ( is => 'rw', isa => 'Str', required => 1, );
has strand           => ( is => 'rw', isa => 'Str', required => 1, );
has transcript_start => ( is => 'rw', isa => 'Int', required => 1, );
has transcript_end   => ( is => 'rw', isa => 'Int', required => 1, );
has coding_start     => ( is => 'rw', isa => 'Int', required => 1, );
has coding_end       => ( is => 'rw', isa => 'Int', required => 1, );

has exon_starts => (
  is       => 'rw',
  isa      => 'ArrayRef[Int]',
  required => 1,
  traits   => ['Array'],
  handles  => {
    all_exon_starts => 'elements',
    get_exon_starts => 'get',
    set_exon_starts => 'set',
  },
);

has exon_ends => (
  is       => 'rw',
  isa      => 'ArrayRef[Int]',
  required => 1,
  traits   => ['Array'],
  handles  => {
    all_exon_ends => 'elements',
    get_exon_ends => 'get',
    set_exon_ends => 'set',
  },
);

has transcript_id => ( is => 'rw', isa => 'Str', required => 1, );

has alt_names => (
  is      => 'rw',
  isa     => 'HashRef[Str]',
  traits  => ['Hash'],
  handles => {
    all_alt_names => 'kv',
    get_alt_names => 'get',
    set_alt_names => 'set',
  },
);

has transcript_seq => (
  is      => 'rw',
  isa     => 'Str',
  builder => '_build_transcript_seq',
  lazy    => 1,
  traits  => ['String'],
  handles => {
    add_transcript_seq      => 'append',
    get_base_transcript_seq => 'substr',
  },
);

has transcript_annotation => (
  is      => 'rw',
  isa     => 'Str',
  builder => '_build_transcript_annotation',
  lazy    => 1,
  traits  => ['String'],
  handles => {
    add_transcript_annotation     => 'append',
    get_str_transcript_annotation => 'substr',
  },
);

has transcript_abs_position => (
  is      => 'rw',
  isa     => 'ArrayRef',
  builder => '_build_transcript_abs_position',
  lazy    => 1,
  traits  => ['Array'],
  handles => {
    get_transcript_abs_position => 'get',
    all_transcript_abs_position => 'elements',
  },
);

has transcript_error => (
  is      => 'rw',
  isa     => 'ArrayRef',
  lazy    => 1,
  builder => '_build_transcript_error',
);

sub BUILD {
  my $self = shift;

  # ensure genome object has the methods we will require - either the
  # string or char genome classes will be fine
  if (  $self->genome_track->meta->has_method('get_abs_pos')
    and $self->genome_track->meta->has_method('get_base') )
  {

    # - get_abs_pos( chr, pos ) expects position to be a positive number
    #   so it is -indexed but returnes the zero-index position
    my $abs_position_offset = $self->get_abs_pos( $self->chr, 1 );

    # - change all relative bp position to absolute positions and change to a
    #   Zero indexed genome (i.e., this is why everything has '-1' taken
    #   from it.
    $self->transcript_start( $abs_position_offset + $self->transcript_start - 1 );
    $self->transcript_end( $abs_position_offset + $self->transcript_end - 1 );
    $self->coding_start( $abs_position_offset + $self->coding_start - 1 );
    $self->coding_end( $abs_position_offset + $self->coding_end - 1 );

    for ( my $i = 0; $i < scalar( $self->all_exon_starts ); $i++ ) {
      # set values for exon starts
      my $abs_pos = $self->get_exon_starts($i) + $abs_position_offset - 1;
      $self->set_exon_starts( $i, $abs_pos );

      # set values for exon stops
      $abs_pos = $self->get_exon_ends($i) + $abs_position_offset - 1;
      $self->set_exon_ends( $i, $abs_pos );
    }
  }
  else {
    confess "Cannot use genome object because it does not have get_abs_pos() method";
  }
}

sub _build_transcript_error {
  my $self = shift;

  # check coding sequence is
  #   1. divisible by 3
  #   2. starts with ATG
  #   3. Ends with stop codon

  # check coding sequence
  my @transcript_annotation = split( //, $self->transcript_annotation );
  my $coding_bases = grep { /ACTG/ } @transcript_annotation;
  my @errors;

  if ( $self->coding_start == $self->coding_end ) {
    return \@errors;
  }
  else {
    if ( $coding_bases % 3 != 0 ) {
      push @errors, 'coding sequence not divisible by 3';
    }

    # check begins with ATG
    if ( $self->transcript_annotation !~ m/\A[5]+ATG/ ) {
      push @errors, 'transcript does not begin with ATG';
    }

    # check stop codon
    if ( $self->transcript_annotation !~ m/(TAA|TAG|TGA)[3]+\Z/ ) {
      push @errors, 'transcript does not end with stop codon';
    }
  }
  return \@errors;
}

sub _build_transcript_abs_position {
  my $self        = shift;
  my @exon_starts = $self->all_exon_starts;
  my @exon_ends   = $self->all_exon_ends;
  my @abs_pos;

  for ( my $i = 0; $i < @exon_starts; $i++ ) {
    for ( my $abs_pos = $exon_starts[$i]; $abs_pos < $exon_ends[$i]; $abs_pos++ ) {
      push @abs_pos, $abs_pos;
    }
  }
  if ( $self->strand eq "-" ) {
    # reverse array
    @abs_pos = reverse @abs_pos;
  }
  return \@abs_pos;
}

# give the sequence with respect to the direction of transcription / coding
sub _build_transcript_seq {

  my $self        = shift;
  my @exon_starts = $self->all_exon_starts;
  my @exon_ends   = $self->all_exon_ends;
  my ($seq);

  for ( my $i = 0; $i < @exon_starts; $i++ ) {
    my $exon;
    for ( my $abs_pos = $exon_starts[$i]; $abs_pos < $exon_ends[$i]; $abs_pos++ ) {
      $exon .= $self->get_base( $abs_pos, 1 );
    }
    #say join ("\t", $exon_starts[$i], $exon_ends[$i], $exon);
    $seq .= $exon;
  }
  if ( $self->strand eq "-" ) {
    # get reverse complement
    $seq = reverse $seq;
    $seq =~ tr/ACGT/TGCA/;
  }
  return $seq;
}

# give the sequence with respect to the direction of transcription / coding
sub _build_transcript_annotation {

  my $self         = shift;
  my @exon_starts  = $self->all_exon_starts;
  my @exon_ends    = $self->all_exon_ends;
  my $coding_start = $self->coding_start;
  my $coding_end   = $self->coding_end;
  my $non_coding   = ( $coding_start == $coding_end ) ? 1 : 0;
  my $seq;

  for ( my $i = 0; $i < @exon_starts; $i++ ) {
    for ( my $abs_pos = $exon_starts[$i]; $abs_pos < $exon_ends[$i]; $abs_pos++ ) {
      if ($non_coding) {
        $seq .= '0';
      }
      else {
        if ( $abs_pos < $coding_end ) {
          if ( $abs_pos >= $coding_start ) {
            $seq .= $self->get_base( $abs_pos, 1 );
          }
          else {
            $seq .= '5';
          }
        }
        else {
          $seq .= '3';
        }
      }
    }
  }
  if ( $self->strand eq "-" ) {
    # flip 5' and 3' UTR distinction and get reverse complement
    $seq = reverse $seq;
    $seq =~ tr/ACGT53/TGCA35/;
  }
  return $seq;
}

sub get_transcript_sites {
  my $self              = shift;
  my @exon_starts       = $self->all_exon_starts;
  my @exon_ends         = $self->all_exon_ends;
  my $coding_start      = $self->coding_start;
  my $coding_end        = $self->coding_end;
  my $coding_base_count = 0;
  my @gene_sites;

  say join( "\t", "transcript: ", $self->transcript_seq );
  say join( "\t", "tran_ann:  ",  $self->transcript_annotation );
  for ( my $i = 0; $i < ( $self->all_transcript_abs_position ); $i++ ) {
    my (
      $annotation_type, $codon_seq, $codon_number,
      $codon_position,  %gene_site, $site_annotation
    );
    $site_annotation = $self->get_str_transcript_annotation( $i, 1 );
    $gene_site{abs_pos}       = $self->get_transcript_abs_position($i);
    $gene_site{base}          = $self->get_base_transcript_seq( $i, 1 );
    $gene_site{error_code}    = $self->transcript_error;
    $gene_site{alt_names}     = $self->alt_names;
    $gene_site{transcript_id} = $self->transcript_id;
    $gene_site{strand}        = $self->strand;

    # is site coding
    if ( $site_annotation =~ m/[ACGT]/ ) {
      $gene_site{annotation_type} = 'Coding';
      $gene_site{codon_number}    = int( ( $coding_base_count / 3 ) ) + 1;
      $gene_site{codon_position}  = $coding_base_count % 3;
      my $codon_start = $i - $gene_site{codon_position};
      my $codon_end   = $codon_start + 2;

      #say "codon_start: $codon_start, codon_end: $codon_end, i = $i, coding_bp = $coding_base_count";
      for ( my $j = $codon_start; $j <= $codon_end; $j++ ) {
        $gene_site{codon_seq} .= $self->get_base_transcript_seq( $j, 1 );
      }
      $coding_base_count++;
    }
    elsif ( $site_annotation eq '5' ) {
      $gene_site{annotation_type} = '5UTR';
    }
    elsif ( $site_annotation eq '3' ) {
      $gene_site{annotation_type} = '3UTR';
    }
    elsif ( $site_annotation eq '0' ) {
      $gene_site{annotation_type} = 'non-coding RNA';
    }
    else {
      confess "unknown site code $site_annotation";
    }
    #p %gene_site if $gene_site{annotation_type} eq 'Coding' and $coding_base_count < 9;
    #exit if $coding_base_count > 9;
    push @gene_sites, Seq::GeneSite->new( \%gene_site );
  }
  return @gene_sites;
}

sub get_flanking_sites {

  # check genoem is a genome sized track or check whether it can give
  # chromosome/position => abs position

  # Annotate splice donor/acceptor bp
  #  - i.e., bp within 6 bp of exon start / stop
  #  - what we want to capture is the bp that are within 6 bp of the start or end of
  #    an exon start/stop; whether this is only within the bounds of coding exons does
  #    not particularly matter to me
  #
  # From the gDNA:
  #
  #        EStart    CStart          EEnd       EStart    EEnd      EStart   CEnd      EEnd
  #        +-----------+---------------+-----------+--------+---------+--------+---------+
  #  Exons  111111111111111111111111111             22222222           333333333333333333
  #  Code               *******************************************************
  #  APR                                        ###                ###
  #  DNR                                %%%                  %%%
  #

  my $self         = shift;
  my @exon_starts  = $self->all_exon_starts;
  my @exon_ends    = $self->all_exon_ends;
  my $coding_start = $self->coding_start;
  my $coding_end   = $self->coding_end;
  my (@gene_sites);

  for ( my $i = 0; $i < @exon_starts; $i++ ) {
    for ( my $n = 1; $n <= $splice_site_length; $n++ ) {

      # flanking sites at start of exon
      if ( $exon_starts[$i] - $n > $coding_start
        && $exon_starts[$i] - $n < $coding_end )
      {
        my %gene_site;
        $gene_site{abs_pos}   = $exon_starts[$i] - $n;
        $gene_site{alt_names} = $self->alt_names;
        $gene_site{annotation_type} =
          ( $self->strand eq "+" ) ? 'Splice Acceptor' : 'Splice Donor';
        $gene_site{base}          = $self->get_base( $gene_site{abs_pos}, 1 );
        $gene_site{error_code}    = $self->transcript_error;
        $gene_site{transcript_id} = $self->transcript_id;
        $gene_site{strand}        = $self->strand;
        push @gene_sites, Seq::GeneSite->new( \%gene_site );
      }
      # flanking sites at end of exon
      if ( $exon_ends[$i] + $n - 1 > $coding_start
        && $exon_ends[$i] + $n - 1 < $coding_end )
      {
        my %gene_site;
        $gene_site{abs_pos}   = $exon_ends[$i] + $n - 1;
        $gene_site{alt_names} = $self->alt_names;
        $gene_site{annotation_type} =
          ( $self->strand eq "+" ) ? 'Splice Donor' : 'Splice Acceptor';
        $gene_site{base}          = $self->get_base( $gene_site{abs_pos}, 1 );
        $gene_site{error_code}    = $self->transcript_error;
        $gene_site{transcript_id} = $self->transcript_id;
        $gene_site{strand}        = $self->strand;
        push @gene_sites, Seq::GeneSite->new( \%gene_site );
      }
    }
  }
  return @gene_sites;
}

__PACKAGE__->meta->make_immutable;

1;
