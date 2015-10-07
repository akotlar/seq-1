use 5.10.0;
use strict;
use warnings;

package Seq::Indel;
# ABSTRACT: Base class for seralizing genomic indels.
# VERSION

=head1 DESCRIPTION
  
  @class B<Seq::Indel>
  #TODO: Check description

  @example

Used in: Seq::Annotate

=cut

use Moose 2;
use Moose::Util::TypeConstraints;

use namespace::autoclean;

use Data::Dump qw/ dump /;

enum IndelType => [ 'Del', 'Ins' ];
enum IndelSiteType => [ '5UTR', 'Coding', '3UTR', 'non-coding RNA',
                       'Splice Donor', 'Splice Acceptor' ];
enum IndelAnnotationType => [ '5UTR', 'Coding', '3UTR', 'non-coding RNA',
                       'Splice Donor', 'Splice Acceptor' ];

my @attributes = qw( abs_pos ref_base transcript_id site_type error_code alt_names genotype annotation_type );

has indel_type => (
  is => 'ro',
  isa => 'IndelType',
  required => 1,
);

has chr => (
  is => 'ro',
  isa => 'Str',
  required => 1,
);

has pos => (
  is => 'ro',
  isa => 'Int',
  required => 1,
);

has abs_start_pos => (
  is       => 'ro',
  isa      => 'Int',
  required => 1,
);

has abs_stop_pos => (
  is => 'ro',
  isa => 'Int',
  required => 1,
);

has ref_annotations =>  (
  traits => ['Array'],
  is        => 'ro',
  isa       => 'ArrayRef',
  required  => 1,
  handles => {
    all_ref_ann => 'elements',
  },
);

has transcripts => (
  traits => ['Hash'],
  is        => 'ro',
  isa       => 'HashRef',
  required  => 1,
  handles => {
    get_tx => 'get',
    keys_tx => 'keys',
  },
);

# ref_annotations => [
# {
#   abs_pos => #
#   gene_data => [
#     {
#       abs_pos => val
#       alt_names => hash_ref
#       ref_base => val
#       site_type => val
#       strand => val
#       transcript_id => val
#     }, ...
#   ]
#   genomic_annotation_code => Intron/Exonic/Intergenic
#   ref_base => val
#   site_code => (used to determine genomic_annotation_code)
# }
# transcripts => {
#   transcriptID (val) => {
#     coding_start            => $gene->coding_start,
#     coding_end              => $gene->coding_end,
#     exon_starts             => $gene->exon_starts,
#     exon_ends               => $gene->exon_ends,
#     transcript_start        => $gene->transcript_start,
#     transcript_end          => $gene->transcript_end,
#     transcript_id           => $gene->transcript_id,
#     transcript_seq          => $gene->transcript_seq,
#     transcript_annotation   => $gene->transcript_annotation,
#     transcript_abs_position => $gene->transcript_abs_position,
#     peptide_seq             => $gene->peptide,
#   },
#  }, ...
#

sub tx_info {
  my $self = shift;

  my %tx;

  for my $site_record ( $self->all_ref_ann ) {

    my $pos = $site_record->{abs_pos};
    my $genomic_annotation_code = $site_record->{genomic_annotation_code};
    my $ref_base = $site_record->{ref_base};

    for my $gene_href ( @{ $site_record->{gene_data} } ) {
      my $tx_id = $gene_href->{transcript_id};
      my $tx_strand = $gene_href->{strand};

      $tx{$tx_id}{$pos} = [ $genomic_annotation_code, $ref_base, $tx_strand, ];
    }
  }
  return \%tx;
}


sub annotate { 
  my $self = shift;

  my $tx_site_href = $self->tx_info;

  for my $tx_id ( $self->keys_tx ) {
    my %res;

    my $tx_href      = $self->get_tx( $tx_id );
    my $tx_start     = $tx_href->{transcript_start};
    my $tx_end       = $tx_href->{transcript_end};
    my $coding_start = $tx_href->{coding_start};
    my $coding_end   = $tx_href->{coding_end};
    my @e_starts     = @{ $tx_href->{exon_starts} };
    my @e_ends       = @{ $tx_href->{exon_ends} };

    my @tx_abs_pos   = @{ $tx_href->{transcript_abs_position} };

    for (my $i = 0; $i < @tx_abs_pos; $i++) {
      if ( $tx_abs_pos[$i] <= $self->abs_stop_pos && $tx_abs_pos[$i] >= $self->abs_start_pos) {
        my $pos = $tx_abs_pos[$i];
        my $ann = substr( $tx_href->{transcript_annotation}, $i, 1 );
        my $genomic_annotation_code = $tx_site_href->{$tx_id}{$tx_abs_pos[$i]}[0];
        my $ref_base = $tx_site_href->{$tx_id}{$tx_abs_pos[$i]}[1];
        my $strand = $tx_site_href->{$tx_id}{$tx_abs_pos[$i]}[2];

      }
    }

    for (my $site = $self->abs_start_pos; $site <= $self->abs_stop_pos; $site++) { 
      my $gen_ann_code = $tx_site_href->{$tx_id}{$site}[0];
      my $ref_base     = $tx_site_href->{$tx_id}{$site}[1];
      my $strand       = $tx_site_href->{$tx_id}{$site}[2];
      for (my $i = 0; $i < @e_starts; $i++) {
        # inside an exon

        if ( $site >= $e_starts[$i] && $site < $e_ends[$i] ) {
          
          # at the exon start/end
          if ($site == $e_starts[$i] || $site == $e_ends[$i] - 1 ) {
            $res{ExonJunction}++;
          }

          # inside coding region
          if ($site >= $coding_start && $site < $coding_end ) {

              # in the start site
              if ($site > $coding_start && $site < ($coding_start + 3) ) {
                $res{CodingStart}++;
                $res{Coding}++;
              }
              # in the stop site
              elsif ( $site < $coding_end && $site > ($coding_end - 3) ) {
                $res{CodingStop}++;
                $res{Coding}++;
              }
              else {
                $res{Coding}++;
              }
            }
          # between tx start and coding start (5' UTR)
          elsif ( $site >= $tx_start && $site < $coding_start ) {
            $res{'5UTR'}++;
          }
          # between tx end and coding end (3' UTR)
          elsif ( $site < $tx_end && $site >= $coding_end ) {
            $res{'3UTR'}++;
          }
        }
        elsif ( $site < $e_starts[$i] && $site < $e_starts[$i] - 6 ) {
          $res{SpliceDonor}++;
        }
        elsif ( $site > $e_ends[$i] && $site < $e_ends[$i] + 6 ) {
          $res{SpliceAcceptor}++;
        }
        elsif( $site > $e_starts[$i] + 6 ) {
          $res{Intronic}++;
        }
        elsif ($site < 

      }
      if (!%res) {
        $res{Intronic}++;
      }
    }

    if (exists $res{Coding} ) {
      if ($res{Coding} % 3 == 0 ) {
        $res{InFrame}++;
      }
      else {
        $res{FrameShift}++;
      }
    }

    # frameshift or inframe implies coding
    my @summary;
    for my $type ( qw/ CodingStart CodingStop FrameShift InFrame 5UTR 3UTR SpliceDonor 
      SpliceAcceptor Intronic / ) {
      if (exists $res{$type}) {
        push @summary, sprintf("%s = %d", $type, $res{$type});
      }
    }
    say dump( { _tx => $tx_id, data => \@summary} );
  }
}

__PACKAGE__->meta->make_immutable;

1;
