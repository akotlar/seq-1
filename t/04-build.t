#!perl -T
use 5.10.0;
use strict;
use warnings;
use Test::More;
use Scalar::Util qw( blessed );

plan tests => 22;

BEGIN
{
  chdir("./sandbox");
  use_ok( 'Seq::Build' ) || print "Bail out!\n";
}

my $hg38_config_file = "hg38.yml";
my $build_hg38 = Seq::Build->new_with_config( configfile => $hg38_config_file );
isa_ok( $build_hg38 'Seq::Build', 'built Seq::Build with config file' );


__END__
my $splice_site_length = 6;

my %idx_codes;
{
  my @bases      = qw(A C G T N);
  my @annotation = qw(0 1);
  my @in_exon    = qw(0 1);
  my @in_gene    = qw(0 1);
  my @is_snp     = qw(0 1);
  my @char       = ( 0 .. 255 );
  my $i          = 0;

  foreach my $base (@bases)
  {
    foreach my $annotation (@annotation)
    {
      foreach my $gene (@in_gene)
      {
        foreach my $exon (@in_exon)
        {
          foreach my $snp (@is_snp)
          {
            $idx_codes{$base}{$annotation}{$gene}{$exon}{$snp} = $char[$i];
            $i++;
          }
        }
      }
    }
  }
}

sub BUILDARGS {
  my $class = shift;
  my $href = $_[0];
  if (scalar @_ > 1 || reftype($href) ne "HASH")
  {
    confess "Error: Seq::Fetch Expected hash reference";
  }
  else
  {
    my %new_hash;
    for my $sparse_track ( @{ $href->{sparse_tracks} } )
    {
      $sparse_track->{genome_name} = $href->{genome_name};
      push @{ $new_hash{sparse_tracks} },
        Seq::Fetch::Sql->new( $sparse_track );
    }
    for my $genome_track ( @{ $href->{genome_sized_tracks} } )
    {
      $genome_track->{genome_chrs} = $href->{genome_chrs};
      push @{ $new_hash{genome_sized_tracks} },
        Seq::Fetch::Files->new( $genome_track );
    }
  for my $attrib (qw( genome_name genome_description genome_chrs
      genome_raw_dir genome_index_dir ))
    {
      $new_hash{$attrib} //= $href->{$attrib} || "";
    }
    return $class->SUPER::BUILDARGS(\%new_hash);
  }
}


sub save_site_and_seralize {
  my $self = shift;
  $sites{$self->abs_pos} = 1;
  return $self->as_href;
};

=head2 _clear_self

=cut

sub clear_all {
  my $self = shift;
  my @attributes = map {$_->name} $self->meta->get_all_attributes;
  for my $attrib (@attributes)
  {
    my $clear_method = "clear\_$attrib";
    $self->$clear_method;
  }
}

=head2 have_annotated_site

=cut

sub have_annotated_site {
  my $self = shift;
  my $site = shift;
  return exists($sites{$site});
}

=head2 have_annotated_site

=cut

sub serialize_sparse_attrs {
  return qw( annotation_type strand codn codon_site_pos aa_residue_pos
    error_code );
}
