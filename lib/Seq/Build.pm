package Seq::Config::Build;

use 5.10.0;
use Carp qw( croak );
use File::Path;
use File::Spec;
use Moose;
use namespace::autoclean;
use Scalar::Util qw( reftype openhandle );
with 'Seq::ConfigFromFile', 'Seq::IO';

=head1 NAME

Seq::Fetch - The great new Seq::Fetch!

=head1 VERSION

Version 0.01

=cut

our $VERSION = '0.01';
my %chr_lens = ( );

has genome_name => ( is => 'ro', isa => 'Str', required => 1, );
has genome_description => ( is => 'ro', isa => 'Str', required => 1, );
has genome_chrs => (
  is => 'ro',
  isa => 'ArrayRef[Str]',
  traits => ['Array'],
  required => 1,
);

# for now, `genome_raw_dir` is really not needed since the other tracks
#   specify a directory and file to use for each feature
has genome_raw_dir => ( is => 'ro', isa => 'Str', required => 1 );
has genome_index_dir => ( is => 'ro', isa => 'Str', required => 1 );
has genome_str_track => (
  is => 'ro',
  isa => 'Seq::GenomeSizedTrackStr',
  required => 1,
);
has genome_sized_tracks => (
  is => 'ro',
  isa => 'ArrayRef[Seq::GenomeSizedTrackChar]',
  required => 1,
);
has snp_tracks => (
  is => 'ro',
  isa => 'ArrayRef[Seq::Build::SnpTrack]',
);
has gene_tracks => (
  is => 'ro',
  isa => 'ArrayRef[Seq::Build::GeneTrack]',
)

=head1 SYNOPSIS

Quick summary of what the module does.

Perhaps a little code snippet.

    use Seq::Config::Build;

    my $foo = Seq::Config::Build->new();
    ...

=head1 SUBROUTINES/METHODS

=head2 function1

=cut

sub build_index {
  my $self = shift;
  $self->build_str_genome;

  # build snp tracks
  my %snp_sites;
  my $snp_tracks_aref = $self->snp_tracks;
  for my $snp_track ( @$snp_tracks_aref )
  {
    my $sites_aref = $snp_track->build_snp_db();
    map { $snp_sites{$_}++ } @$sites_aref;
  }

  # build gene tracks
  my (%flank_exon_sites, %exon_sites, $tx_start_href);
  my $gene_tracks_aref = $self->gene_tracks;
  for my $gene_track ( @$gene_tracks_aref )
  {
    my ($flank_exon_sites_aref, $exon_sites_aref, $trans_coord_href)
      = $gene_track->build_gene_db();
    map { $flank_exon_sites{$_}++ } @$flank_exon_sites_aref;
    map { $exon_sites{$_}++ } @$exon_sites;
  }

  # make another genomesized track to deal with the in/outside of genes
  # and ultimately write over those 0's and 1's to store the genome assembly
  # idx codes...
  my $assembly = Seq::Build::GenomeSizedTrackChar->new(
    { length => "$chr_len{genome}", $self->genome_index_dir,
      name => $self->genome_name,
      type => 'genome',
      genome_chrs => $self->genome_chrs,
    }
  );

  # set genic/intergenic regions
  $assembly->set_gene_regions( $tx_start_href );

  # use gene, snp tracks, and genic/intergenic regions to build coded genome
  $assembly->build_idx( $self->genome_str_track, \%exon_sites, \%flank_exon_sites, \%snp_sites );
  $assembly->write_char_seq;
  $assembly->clear_char_seq;

  # set and write scores for conservation tracks / i.e., the other GenomeSized
  # Tracks
  $self->build_genome_sized_tracks;
  $self->write_genome_sized_tracks;
}

sub build_str_genome {
  my $self = shift;
  my $genome_str_track     = $self->genome_str_track;
  my $local_dir        = File::Spec->canonpath( $genome_str_track->local_dir );
  my $local_files_aref = $genome_str_track->loacl_files;
  my $genome_chrs_aref = $genome_str_track->genome_chrs;
  my $abs_pos = 0;

  for my $i (0 .. $#local_files_aref)
  {
    my $file       = $local_file_aref[$i];
    my $chr        = $genome_chrs_aref[$i];
    my @file_fields = split(/\./, $file);
    croak "expected chromosomes and sequence files to be in the
           same order but found $file with $chr\n"
           unless $chr eq $file_fields[0];

    my $local_file = File::Spec->cannonpath( $local_dir, $file );
    my $in_fh      = $self->get_fh( $local_file );
    $chr_len{$chr} = $abs_pos;
    while ( my $line = $in_fh->getline() )
    {
      chomp $line;
      $line =~ s/\s+//g;
      next if ( $line =~ m/\A>/ );
      $genome_str_track->push_str( $line );
      $abs_pos += length $line;
    }
  }
  $chr_len{genome} = $abs_pos;
}

sub build_genome_sized_tracks {
  my $self = shift;
  my $genome_sized_tracks_aref = $self->genome_sized_tracks;

  foreach my $gst ( @$genome_sized_tracks_aref )
  {
    $gst->length         = $chr_len{genome};
    $gst->score2char     = $convert{encode}{$gst->type};
    my $local_dir        = File::Spec->canonpath( $gst->local_dir );
    my $local_files_aref = $gst->loacl_files;
    # there's only 1 file (at the moment) for all conservation stuff
    for my $i (0 .. $#local_files_aref)
    {
      my $file       = $local_file_aref[$i];
      my $local_file = File::Spec->cannonpath( $local_dir, $file );
      my $in_fh      = $self->get_fh( $local_file );
      while ( my $line = $in_fh->getline() )
      {
        chomp $line;
        my ( $chr, $pos, $score ) = split( /\t/, $line );
        $gst->insert_score( $self->get_abs_pos( $chr, $pos ), $score );
      }
    }
  }
}

sub write_genome_sized_tracks {
  my $self = shift;
  my $genome_sized_tracks_aref = $self->genome_sized_tracks;
  foreach my $gst ( @$genome_sized_tracks_aref )
  {
    $gst->write_char_seq;
    $gst->clear_char_seq;
  }
}

sub BUILDARGS {
  my $class = shift;
  my $href  = $_[0];
  if (scalar @_ > 1) || reftype($href) ne "HASH")
  {
    confess "Error: Seq::Build expects hash reference.\n";
  }
  else
  {
    my %hash;
    for my $sparse_track ( @{ $href->{sparse_tracks} } )
    {
      $sparse_track->{genome_name} = $href->{genome_name};
      if ($sparse_track->{type} eq "gene")
      {
        push @{ $hash{gene_tracks} }, Seq::Build::GeneTrack->new( $sparse_track );
      }
      elsif ( $sparse_track->{type} eq "snp" )
      {
        push @{ $hash{snp_tracks} }, Seq::Build::SnpTrack->new( $sparse_track );
      }
      else
      {
        croak "unrecognized sparse track type $sparse_track->{type}\n";
      }
    }
    for my $genome_str_track ( @{ $href->{genome_sized_tracks} } )
    {
      $genome_str_track->{genome_chrs} = $href->{genome_chrs};
      if ($genome_str_track->{type} eq "genome")
      {
        $hash{genome_str_track} = Seq::Build::GenomeSizedTrackStr->new( $genome_str_track );
      }
      elsif ( $genome_str_track->{type} eq "phastCons"
              or $genome_str_track->{type} eq "phyloP" )
      {
        push @{ $hash{genome_sized_tracks} },
          Seq::Build::GenomeSizedTrackChar->new( $genome_str_track );
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
    return $class->SUPER::BUILDARGS(\%hash);
  }
}

=head2 function2

=cut

sub get_abs_pos {
  my $self = shift;
  my ( $chr, $pos ) = @_;
  my $abs_pos = $chr_len{$chr} + $pos;
  return $abs_pos;
}

=head1 AUTHOR

Thomas Wingo, C<< <thomas.wingo at emory.edu> >>

=head1 BUGS

Please report any bugs or feature requests to C<bug-seq at rt.cpan.org>, or through
the web interface at L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=Seq>.  I will be notified, and then you'll
automatically be notified of progress on your bug as I make changes.




=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc Seq::Config::Build


You can also look for information at:

=over 4

=item * RT: CPAN's request tracker (report bugs here)

L<http://rt.cpan.org/NoAuth/Bugs.html?Dist=Seq>

=item * AnnoCPAN: Annotated CPAN documentation

L<http://annocpan.org/dist/Seq>

=item * CPAN Ratings

L<http://cpanratings.perl.org/d/Seq>

=item * Search CPAN

L<http://search.cpan.org/dist/Seq/>

=back


=head1 ACKNOWLEDGEMENTS


=head1 LICENSE AND COPYRIGHT

Copyright 2015 Thomas Wingo.

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program.  If not, see L<http://www.gnu.org/licenses/>.


=cut

__PACKAGE__->meta->make_immutable;

1; # End of Seq::Config::Build
