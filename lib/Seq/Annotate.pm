package Seq::Annotate;

use 5.10.0;
use Carp qw( croak );
use Moose;
use namespace::autoclean;
use Scalar::Util qw( reftype );
use DDP;

with 'Seq::Role::IO', 'MooX::Role::Logger', 'MooseX::Role::MongoDB';

has genome_track => (
  is => 'ro',
  isa => 'Seq::GenomeSizedTrackStr',
  required => 1,
  handles => [ 'get_abs_pos', 'get_base', 'genome_length', 'get_idx_base',
    'get_idx_in_gan', 'get_idx_in_gene', 'get_idx_in_exon', 'get_idx_in_snp',
  ],
);

has genome_sized_tracks => (
  is => 'ro',
  isa => 'ArrayRef[Seq::GenomeSizedTrackStr]',
  traits => ['Array'],
  handles => {
    all_genome_sized_tracks => 'elements',
    add_genome_sized_track  => 'push',
  },
);

has _gene_dbs => (
  is => 'ro',
  isa => 'ArrayRef[MongoDB::Collection]',
  trait => ['Array'],
  handles => [ 'get_gene_site_annotation' ],
  builder => '_build_gene_dbs',
  lazy => 1,
);

has _snp_dbs => (
  is => 'ro',
  isa => 'ArrayRef[MongoDB::Collection]',
  trait => ['Array'],
  handles => [ 'get_snp_site_annotation' ],
  builder => '_build_gene_dbs',
  lazy => 1,
);

has database => (
    is       => 'ro',
    isa      => 'Str',
    required => 1,
);

has client_options => (
    is       => 'ro',
    isa      => 'HashRef',
    default  => sub { {} },
);

sub _build__mongo_default_database { return $_[0]->database }
sub _build__mongo_client_options   { return $_[0]->client_options }

sub annotate_site {
  my ($self, $chr, $pos) = shift;

  my %record;

  # check chr and pos exist

  my $site_code = $self->get_base( $chr, $pos );
  my $base      = $gct->get_idx_base( $base_code );
  my $gan       = ($gct->get_idx_in_gan( $base_code )) ? 1 : 0;
  my $gene      = ($gct->get_idx_in_gene( $base_code )) ? 1 : 0;
  my $exon      = ($gct->get_idx_in_exon( $base_code )) ? 1 : 0;
  my $snp       = ($gct->get_idx_in_snp( $base_code )) ? 1 : 0;

  if ($gan)
  {
    # lookup gene annotation
  }

  if ($snp)
  {
    # lookup snp annotation
  }

  return \%record;
}

sub BUILD {
  # open the mongo db for the tracks
  # open the genome file here and give it to GenomeSizedTrackChar
}


sub BUILDARGS {
  my $class = shift;
  my $href  = $_[0];
  if (scalar @_ > 1 || reftype($href) ne "HASH")
  {
    confess "Error: $class expects hash reference.\n";
  }
  else
  {
    my %hash;
    for my $sparse_track ( @{ $href->{sparse_tracks} } )
    {
      $sparse_track->{genome_name} = $href->{genome_name};
      if ($sparse_track->{type} eq "gene")
      {
        push @{ $hash{gene_tracks} }, Seq::Config::SparseTrack->new( $sparse_track );
      }
      elsif ( $sparse_track->{type} eq "snp" )
      {
        push @{ $hash{snp_tracks} }, Seq::Config::SparseTrack->new( $sparse_track );
      }
      else
      {
        croak "unrecognized sparse track type $sparse_track->{type}\n";
      }
    }

    # TODO: change genome_str_track to genome_track
    for my $genome_str_track ( @{ $href->{genome_sized_tracks} } )
    {
      $genome_str_track->{genome_chrs} = $href->{genome_chrs};
      $genome_str_track->{genome_index_dir} = $href->{genome_index_dir};

      if ($genome_str_track->{type} eq "genome")
      {
        $hash{genome_track} = Seq::GenomeSizedTrackChar->new( $genome_str_track );
      }
      elsif ( $genome_str_track->{type} eq "score" )
      {
        push @{ $hash{genome_sized_tracks} },
          Seq::Config::GenomeSizedTrack->new( $genome_str_track );
      }
      else
      {
        croak "unrecognized genome track type $genome_str_track->{type}\n"
      }
    }
    for my $attrib (qw( genome_name genome_description genome_chrs
      genome_raw_dir genome_index_dir ))
    {
      $hash{$attrib} //= $href->{$attrib} || "";
    }
    if (exists $attrib->{host})
    {
      my $port //= $attrib->{port} || '27017';
      my $host //= $attrib->{host} || "mongodb://$host:$port";
      $hash{database} = $hash{genome_name};
      $hash{client_options} = { host => $host };
    }
    return $class->SUPER::BUILDARGS(\%hash);
  }
}
