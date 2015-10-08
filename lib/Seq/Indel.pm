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

has splice_site_length => (
  is => 'ro',
  isa => 'Int',
  default => 6,
  required => 1,
);

has _tx_alt_names => (
  traits => ['Hash'],
  is        => 'ro',
  isa       => 'HashRef[HashRef]',
  required  => 1,
  handles => {
    get_alt_name => 'get',
    set_alt_name => 'set',
  },
  default => sub {{ }},
);

has _tx_strand => (
  traits => ['Hash'],
  is        => 'ro',
  isa       => 'HashRef[Str]',
  required  => 1,
  handles => {
    get_tx_strand => 'get',
    set_tx_strand => 'set',
  },
  default => sub {{ }},
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
sub as_href {
  my $self = shift;
  if ($self->indel_type eq 'Del' ) {
    return $self->_annotate_del;
  }
  else {
    return $self->_annotate_ins;
  }
}

sub _site_2_tx {
  my $self = shift;

  my %site_2_tx;

  for my $site_record ( $self->all_ref_ann ) {

    my $pos = $site_record->{abs_pos};

    for my $attr (qw/ ref_base genomic_annotation_code/ ) {
      $site_2_tx{$pos}{$attr} = $site_record->{$attr};
    }

    for my $gene_href ( @{ $site_record->{gene_data} } ) {
      push @{ $site_2_tx{$pos}{transcript_id} }, $gene_href->{transcript_id};
      $self->set_alt_name( $gene_href->{transcript_id} => $gene_href->{alt_names} );
      $self->set_tx_strand( $gene_href->{transcript_id} => $gene_href->{strand} );
    }
  }
  return \%site_2_tx;
}
sub _annotate_del {
  my $self = shift;

  my $tx_site_href = $self->_site_2_tx;

  # {
  #   "2803214660" => {
  #     genomic_annotation_code => "Exonic",
  #     ref_base => "A",
  #     transcript_id => ["NM_001197297", "NM_002040"],
  #   },
  # }

  my (%tx, %ann, @ref_bases);
  for (my $site = $self->abs_start_pos; $site <= $self->abs_stop_pos; $site++) {
    push @ref_bases, $tx_site_href->{$site}{ref_base};
    for my $tx_id ( @{ $tx_site_href->{$site}{transcript_id} } ) {
      my $dat = $self->_ann_tx_site( $tx_id, $site );
      for my $type ( keys %$dat ) {
        $tx{$tx_id}{$type}++;
      }
    }
  }

  for my $tx_id ( keys %tx) {
    if (exists $tx{$tx_id}{Coding}) {
      if ($tx{$tx_id}{Coding} % 3 == 0) {
        $tx{$tx_id}{InFrame}++;
      }
      else {
        $tx{$tx_id}{FrameShift}++;
      }
    }
    my @site_types = qw/ Exonic Coding Intronic /;
    my @annotation_types = qw/ 5UTR 3UTR SpliceDonor SpliceAcceptor
      StartLoss StopLoss FrameShift InFrame /;

    my @site_type_summary;
    for my $type (@site_types) {
      if (exists $tx{$tx_id}{$type} ) {
        push @site_type_summary, $type;
      }
    }

    my @ann_type_summary;
    for my $type ( @annotation_types ) {
      if (exists $tx{$tx_id}{$type}) {
        push @ann_type_summary, $type;
      }
    }
    if (!@ann_type_summary ){
      push @ann_type_summary, 'Del';
    }
    push @{ $ann{site_type} }, join(",", @site_type_summary);
    push @{ $ann{annotation_type} }, join(",", @ann_type_summary);
    push @{ $ann{transcript_id} }, $tx_id;
    push @{ $ann{alt_names} }, $self->get_alt_name( $tx_id );
  }
  $ann{chr} = $self->chr;
  $ann{pos} = $self->pos;
  $ann{ref_base} = join "", @ref_bases;

  say dump( \%ann );
  return \%ann;
}

sub _ann_tx_site {
  my ($self, $tx_id, $site) = @_;

  my %res;
  my $splice_site_length = $self->splice_site_length;
  my $tx_href      = $self->get_tx( $tx_id );
  my $strand       = $self->get_tx_strand( $tx_id );
  my $tx_start     = $tx_href->{transcript_start};
  my $tx_end       = $tx_href->{transcript_end};
  my $coding_start = $tx_href->{coding_start};
  my $coding_end   = $tx_href->{coding_end};
  my @e_starts     = @{ $tx_href->{exon_starts} };
  my @e_ends       = @{ $tx_href->{exon_ends} };

  # loop over exons
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
          if ($site >= $coding_start && $site < ($coding_start + 3) ) {
            say join "\t", "Start Coding ", $site;
            $res{StartLoss}++;
            $res{Coding}++;
          }
          # in the stop site
          elsif ( $site >= ($coding_end - 3) && $site < $coding_end ) {
            say join "\t", "Stop Coding ", $site;
            $res{StopLoss}++;
            $res{Coding}++;
          }
          else {
            say join "\t", "Coding ", $site;
            $res{Coding}++;
          }
        }
      # between tx start and coding start (5' UTR)
      elsif ( $site >= $tx_start && $site < $coding_start ) {
        $res{'5UTR'}++;
        $res{Exonic}++;
      }
      # between tx end and coding end (3' UTR)
      elsif ( $site >= $coding_end && $site < $tx_end ) {
        $res{'3UTR'}++;
        $res{Exonic}++;
      }
    }
    elsif ( $site < $e_starts[$i] && $site > ($e_starts[$i] - $splice_site_length) ) {
      $res{SpliceDonor}++;
      $res{Intronic}++;
    }
    elsif ( $site > $e_ends[$i] && $site < ($e_ends[$i] + $splice_site_length)  ) {
      $res{SpliceAcceptor}++;
      $res{Intronic}++;
    }
  }
  if (!%res) {
    $res{Intronic}++;
  }
  return \%res;
}

__PACKAGE__->meta->make_immutable;

1;
