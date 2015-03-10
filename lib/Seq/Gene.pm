package Seq::Gene;

use 5.10.0;
use Carp qw( croak );
use Moose;
use namespace::autoclean;

# has features of a gene and will run through the sequence
# build features will be implmented in Seq::Build::Gene that can build GeneSite
# objects
# would be useful to extend to have capcity to build peptides

my $splice_site_length = 6;

has genome => (
  is => 'ro',
  required => 1,
  handles => [ 'get_abs_pos', 'get_base', ],
);

has chr => (
  is => 'rw',
  isa => 'Str',
  required => 1,
);

has strand => (
  is => 'rw',
  isa => 'Str',
  required => 1,
);

has transcript_start => (
  is => 'rw',
  isa => 'Int',
  required => 1,
);

has transcript_end => (
  is => 'rw',
  isa => 'Int',
  required => 1,
);

has coding_start => (
  is => 'rw',
  isa => 'Int',
  required => 1,
);

has coding_end => (
  is => 'rw',
  isa => 'Int',
  required => 1,
);

has exon_starts => (
  is => 'rw',
  isa => 'ArrayRef[Int]',
  required => 1,
  traits => ['Array'],
  handles => {
    all_exon_starts => 'elements',
    get_exon_starts => 'get',
    set_exon_starts => 'set',
  },
);

has exon_stops => (
  is => 'rw',
  isa => 'ArrayRef[Int]',
  required => 1,
  traits=> ['Array'],
  handles => {
    all_exon_stops => 'elements',
    get_exon_stops => 'get',
    set_exon_stops => 'set',
  },
);

has transcript_id => (
  is => 'rw',
  isa => 'Str',
  required => 1,
);

has alt_names => (
  is => 'rw',
  isa => 'ArrayRef[Str]',
  traits => ['Array'],
  handles => {
    all_alt_names => 'elements',
  },
);

has transcript_start_stop_history => (
  is => 'rw',
  isa => 'HashRef',

);

has transcript_seq => (
  is => 'rw',
  isa => 'Str',
  builder => '_build_transcript_seq',
  lazy => 1,
  traits => ['String'],
  handles => {
    add_transcript_seq => 'append',
    get_base_transcript_seq => 'substr',
  },
);

has transcript_annotation => (
  is => 'rw',
  isa => 'Str',
  builder => '_build_transcript_annotation',
  lazy => 1,
  traits => ['String'],
  handles => {
    add_transcript_annotation => 'append',
    get_str_transcript_annotation => 'substr',
  },
);

has transcript_abs_position => (
  is => 'rw',
  isa => 'ArrayRef',
  builder => '_build_transcript_abs_position',
  lazy => 1,
  traits => ['Array'],
  handles => {
    get_transcript_abs_position => 'get',
    all_transcript_abs_position => 'elements',
    add_transcript_abs_position => 'push',
    sort_transcript_abs_position => 'sort_in_place',
  },
);

has transcript_error => (
  is => 'rw',
  isa => 'ArrayRef',
  lazy => 1,
  builder => '_build_transcript_error',
);


sub BUILD {
  my $self = shift;

  # ensure genome object is usable
  if ($self->genome->meta->has_method( 'get_abs_pos' ))
  {
    # change all relative bp position to absolute positions
    my $abs_position_offset  = $self->get_abs_pos( $self->chr, 0 );
    $self->transcript_start += $abs_position_offset;
    $self->transcript_stop  += $abs_position_offset;
    $self->coding_start     += $abs_position_offset;
    $self->coding_stop      += $abs_position_offset;

    for (my $i = 0; $i < scalar ( $self->all_exon_starts ); $i++)
    {
      # set values for exon starts
      my $abs_pos = $self->get_exon_starts( $i ) + $abs_position_offset;
      $self->set_exon_starts( $i, $abs_pos );
      
      # set values for exon stops
      $abs_pos = $self->get_exon_stops( $i ) + $abs_position_offset;
      $self->set_exon_stops( $i, $abs_pos );
    }
  }
  else
  {
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
  my @transcript_annotation = split(//, $self->transcript_annotation);
  my $coding_bases = grep { /ACTG/ } @transcript_annotation;

  my @errors;
  if ($coding_bases % 3 != 0) 
  {
    push @errors, 'coding sequence not divisible by 3';
  }

  # check begins with ATG
  if ($self->transcript_seq !~ m/\A5+ATG/)
  {
    push @errors, 'transcript does not begin with ATG';
  }

  # check stop codon
  if ($self->transcript_seq !~ m/(TAA|TAG|TGA)3+\Z/)
  {
    push @errors, 'transcript does not end with stop codon';
  }
}

sub _build_transcript_abs_position {
  my $self = shift;
  my @exon_starts = $self->all_exon_starts;
  my @exon_stops  = $self->all_exon_stops;

  for (my $i = 0; $i < @exon_starts; $i++)
  {
    for (my $abs_pos = $exon_starts[$i]; $abs_pos <= $exon_starts[$i]; $abs_pos++)
    {
      $self->add_transcript_abs_position( $abs_pos );
    }
  }
  if ($self->strand eq "-")
  {
    # reverse array
    $self->sort_transcript_abs_position( sub { $_[1] <=> $_[0] } );
    #my @rev_tx_abs_pos = reverse $self->all_transcript_abs_position();
    #$self->transcript_abs_position = \@rev_tx_abs_pos;
  }
}


# give the sequence with respect to the direction of transcription / coding
sub _build_transcript_seq {

  my $self = shift;
  my @exon_starts = $self->all_exon_starts;
  my @exon_stops  = $self->all_exon_stops;

  for (my $i = 0; $i < @exon_starts; $i++)
  {
    for (my $abs_pos = $exon_starts[$i]; $abs_pos <= $exon_starts[$i]; $abs_pos++)
    {
      $self->add_transcript_seq( $self->get_base( $abs_pos ) );
    }
  }
  if ($self->strand eq "-")
  {
    my $rev_tx_str = reverse $self->transcript_seq;
    $rev_tx_str =~ tr/ACGT/TGCA/;
    $self->transcript_seq = $rev_tx_str;
  }
}

# give the sequence with respect to the direction of transcription / coding
sub _build_transcript_annotation {

  my $self = shift;
  my @exon_starts    = $self->all_exon_starts;
  my @exon_stops     = $self->all_exon_stops;
  my $coding_start   = $self->coding_start;
  my $coding_end     = $self->coding_stop;

  # TODO: add non coding handling

  for (my $i = 0; $i < @exon_starts; $i++)
  {
    for (my $abs_pos = $exon_starts[$i]; $abs_pos <= $exon_starts[$i]; $abs_pos++)
    {
      if ( $abs_pos < $coding_end )
      {
        if ( $abs_pos >= $coding_start )
        {
          $self->add_transcript_annotation( $self->get_base( $abs_pos ) );
        }
        else
        {
          $self->add_transcript_annotation ( '5' );
        }
      }
      else
      {
        $self->add_transcript_annotation ( '3' );
      }
    }
  }
  if ($self->strand eq "-")
  {
    my $rev_tx_str = reverse $self->transcript_seq;
    $rev_tx_str =~ tr/53/35/;
    $self->transcript_seq = $rev_tx_str;
  }
}

sub get_transcript_sites {
  my $self = shift;
  my @exon_starts  = $self->all_exon_starts;
  my @exon_stops   = $self->all_exon_stops;
  my $coding_start = $self->coding_start;
  my $coding_end   = $self->coding_stop;


  # check coding sequence is 
  #   1. divisible by 
  #   2. starts with ATG
  #   3. Ends with stop codon

  for (my $i = 0; $i < ($self->all_transcript_abs_position); $i++)
  {
    my $abs_pos         = $self->get_transcript_abs_position( $i );
    my $base            = $self->get_base_transcript_seq( $i, 1 );
    my $site_annotation = $self->get_str_transcript_annotation( $i, 1 );

    # is site coding
    if ($site_annotation =~ m/ACGT/)
    {


    }
    elsif ($site_annotation eq '5')
    {

    }
    elsif ($site_annotation eq '3')
    {

    }
    else
    {
      croak "unknown site code $site_annotation";
    }
  }
}

sub get_flanking_sites {
  my ($self, $genome) = @_;

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

  my @exon_starts = $self->all_exon_starts;
  my @exon_stops  = $self->all_exon_stops;
  my $coding_start = $genome->get_abs_pos( $self->chr, $self->coding_start );
  my $coding_end = $genome->get_abs_pos( $self->chr, $self->coding_end );
  my @sites;

  for (my $i = 0; $i < @exon_starts; $i++)
  {
    for ( my $n = 1; $n <= $splice_site_length; $n++ )
    {
      # flanking sites at start of exon
      if ( $self->in_coding_region( $exon_starts[$i] - $n ) )
      {
        my $site     = $exon_starts[$i] - $n;
        my $abs_site = $genome->get_abs_pos( $self->chr, $site );
        my $annotation_type = ($self->strand eq "+") ? 'Splice Donor' : 'Splice Acceptor';
        my $gene_site = Seq::GeneSite->new( {
          abs_pos => $abs_site, name => $self->transcript_id,
          annotation_type => $annotation_type, strand-> $self->strand,
          error_code => 0,
        });
        push @sites, $gene_site;
      }
      # flanking sites at end of exon
      if ( $self->in_coding_region( $exon_stops[$i] + $n ))
      {
        my $site     = $exon_stops[$i] + $n;
        my $abs_site = $genome->get_abs_pos( $self->chr, $site );
        my $annotation_type = ($self->strand eq "+") ? 'Splice Acceptor': 'Splice Donor';
        my $gene_site = Seq::GeneSite->new( {
          abs_pos => $abs_site, name => $self->transcript_id,
          annotation_type => $annotation_type, strand-> $self->strand,
          error_code => 0,
        });
        push @sites, $gene_site;
      }
    }
  }
  return @sites;
}

__PACKAGE__->meta->make_immutable;

1; # End of Seq::GeneTrack
