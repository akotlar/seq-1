package Seq::Build::SnpTrack;

use 5.10.0;
use Carp qw( confess );
use Moose;
use Moose::Util::TypeConstraints;
use namespace::autoclean;
use Scalar::Util qw( reftype );
use Cpanel::JSON::XS;

use Seq::Build::GenomeSizedTrackStr;
use Seq::SnpSite;

use DDP;

extends qw( Seq::Config::SparseTrack );
with qw( Seq::Role::IO );

=head1 NAME

Seq::Build::SnpTrack - The great new Seq::Build::SnpTrack!

=head1 VERSION

Version 0.01

=cut

our $VERSION = '0.01';

has genome_index_dir => (
  is => 'ro',
  isa => 'Str',
  required => 1,
);

has genome_name => (
  is => 'ro',
  isa => 'Str',
  required => 1,
);

has genome_seq => (
  is => 'ro',
  isa => 'Seq::Build::GenomeSizedTrackStr',
  required => 1,
  handles => [ 'get_abs_pos', 'get_base', ],
);

has host => (
  is => 'ro',
  isa => 'Str',
  default => '127.0.0.1',
);

=head1 SYNOPSIS

Quick summary of what the module does.

Perhaps a little code snippet.

    use Seq::Build::SnpTrack;

    my $foo = Seq::Build::SnpTrack->new();
    ...

=head1 EXPORT

A list of functions that can be exported.  You can delete this section
if you don't export anything, such as for a purely object-oriented module.

=head1 SUBROUTINES/METHODS

=head2 function1

=cut

sub build_snp_db {
  my $self = shift;

  #
  # TODO - ?Deligate Mongo? for testing when we don't have mongo running?
  #        could only invoke when we are passed a host...
  #        same goes for Seq::Build::GeneTrack
  #
  my $client = MongoDB::MongoClient->new(host => "mongodb://" . $self->host)
    or confess "Cannot connect to MongoDb at " .. $self->host;

  my $db = $client->get_database( $self->genome_name )
    or confess "Cannot access MongoDb database: " . $self->genome_name;

  my $gene_collection = $db->get_collection( $self->name )
    or confess "Cannot access MongoDb collection: " . $self->name
    . "from database: " . $self->genome_name;

  $gene_collection->drop;

  # input
  my $local_dir     = File::Spec->canonpath( $self->local_dir );
  my $local_file    = File::Spec->catfile( $local_dir, $self->local_file );
  my $in_fh         = $self->get_read_fh( $local_file );

  # output
  my $out_dir       = File::Spec->canonpath( $self->genome_index_dir);
  File::Path->make_path( $out_dir );
  my $out_file_name = join(".", $self->genome_name, $self->name, $self->type,  'json' );
  my $out_file_path = File::Spec->catfile( $out_dir, $out_file_name );
  my $out_fh        = $self->get_write_fh( $out_file_path );

  my (%header, @snp_sites);
  my $prn_counter = 0;
  while(<$in_fh>)
  {
    chomp $_;
    my @fields = split(/\t/, $_);
    if ($. == 1)
    {
      map { $header{$fields[$_]} = $_ } (0..$#fields);
      next;
    }
    my %data = map { $_ => $fields[ $header{$_} ] } @{ $self->snp_fields_aref };
    my ( $allele_freq_count, @alleles, @allele_freqs, $min_allele_freq );

    if ( $data{alleleFreqCount} )
    {
      @alleles      = split( /,/, $data{alleles} );
      @allele_freqs = split( /,/, $data{alleleFreqs} );
      my @s_allele_freqs = sort { $b <=> $a } @allele_freqs;
      $min_allele_freq = sprintf( "%0.6f", 1 - $s_allele_freqs[0]);
    }

    if ( $data{name} =~ m/^rs(\d+)/ )
    {
      foreach my $pos ( ( $data{chromStart} + 1 ) .. $data{chromEnd} )
      {
        my $chr    = $data{chrom};
        my $snp_id = $data{name};
        my $abs_pos = $self->get_abs_pos( $chr, $pos );
        my $record  = { abs_pos => $abs_pos,
                        snp_id  => $snp_id,
                      };
        my $snp_site = Seq::SnpSite->new( $record );
        my $base = $self->get_base( $abs_pos, 1 );
        $snp_site->set_feature( base => $base );
        #say "chr: $chr, pos: $pos, abs_pos: $abs_pos";

        if ($min_allele_freq)
        {
          $snp_site->set_feature( maf => $min_allele_freq, alleles => join(",", @alleles));
        }
        push @snp_sites, $abs_pos;

        my $site_href = $snp_site->as_href;
        $gene_collection->insert( $site_href );

        if ($prn_counter == 0)
        {
          print { $out_fh } "[" . encode_json( $snp_site->as_href );
          $prn_counter++;
        }
        else
        {
          print { $out_fh } "," . encode_json( $snp_site->as_href );
          $prn_counter++;
        }
      }
    }
  }
  print { $out_fh } "]";
  return \@snp_sites;
}

=head1 AUTHOR

Thomas Wingo, C<< <thomas.wingo at emory.edu> >>

=head1 BUGS

Please report any bugs or feature requests to C<bug-seq-build-genetrack at rt.cpan.org>, or through
the web interface at L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=Seq-Build-GeneTrack>.  I will be notified, and then you'll
automatically be notified of progress on your bug as I make changes.




=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc Seq::Build::SnpTrack


You can also look for information at:

=over 4

=item * RT: CPAN's request tracker (report bugs here)

L<http://rt.cpan.org/NoAuth/Bugs.html?Dist=Seq-Build-GeneTrack>

=item * AnnoCPAN: Annotated CPAN documentation

L<http://annocpan.org/dist/Seq-Build-GeneTrack>

=item * CPAN Ratings

L<http://cpanratings.perl.org/d/Seq-Build-GeneTrack>

=item * Search CPAN

L<http://search.cpan.org/dist/Seq-Build-GeneTrack/>

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

1; # End of Seq::Build::SnpTrack
