package Seq::Build::GeneTrack;

use 5.10.0;
use Carp qw( confess );
use Moose;
use Moose::Util::TypeConstraints;
use namespace::autoclean;
use Scalar::Util qw( reftype );
use Cpanel::JSON::XS;
use MongoDB;

use Seq::Gene;
use Seq::Build::GenomeSizedTrackStr;


use DDP;

extends qw( Seq::Config::SparseTrack );
with qw( Seq::Role::IO );

=head1 NAME

Seq::Build::GeneTrack - The great new Seq::Build::GeneTrack!

=head1 VERSION

Version 0.01

=cut

our $VERSION = '0.01';

$MongoDB::BSON::looks_like_number = 1;

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

has genome_track_str => (
  is => 'ro',
  isa => 'Seq::Build::GenomeSizedTrackStr',
  required => 1,
  handles => [ 'get_abs_pos', 'get_base', ],
);

has mongo_connection => (
  is => 'ro',
  isa => 'Seq::MongoManager',
  required => 1,
);

=head1 SYNOPSIS

Quick summary of what the module does.

Perhaps a little code snippet.

    use Seq::Build::GeneTrack;

    my $foo = Seq::Build::GeneTrack->new();
    ...

=head1 EXPORT

A list of functions that can be exported.  You can delete this section
if you don't export anything, such as for a purely object-oriented module.

=head1 SUBROUTINES/METHODS

=head2 function1

=cut

sub build_gene_db {
  my $self = shift;

  #
  # TODO - ?Deligate Mongo? for testing when we don't have mongo running?
  #        could only invoke when we are passed a host...
  #        same goes for Seq::Build::GeneTrack
  #
  # my $client = MongoDB::MongoClient->new(host => "mongodb://" . $self->host)
  #   or confess "Cannot connect to MongoDb at " .. $self->host;
  #
  # my $db = $client->get_database( $self->genome_name )
  #   or confess "Cannot access MongoDb database: " . $self->genome_name;
  #
  # my $gene_collection = $db->get_collection( $self->name )
  #   or confess "Cannot access MongoDb collection: " . $self->name
  #   . "from database: " . $self->genome_name;
  #
  # $gene_collection->drop;
  $self->mongo_connection->_mongo_collection( $self->name );
  $self->mongo_connection->_mongo_collection( $self->name )->drop;

  # input
  my $local_dir     = File::Spec->canonpath( $self->local_dir );
  my $local_file    = File::Spec->catfile( $local_dir, $self->local_file );
  my $in_fh         = $self->get_read_fh( $local_file );

  # output
  my $out_dir       = File::Spec->canonpath( $self->genome_index_dir );
  File::Path->make_path( $out_dir );
  my $out_file_name = join(".", $self->genome_name, $self->name, $self->type, 'json' );
  my $out_file_path = File::Spec->catfile( $out_dir, $out_file_name );
  my $out_fh        = $self->get_write_fh( $out_file_path );

  my %ucsc_table_lu = ( alignID => 'transcript_id', chrom => 'chr', cdsEnd => 'coding_end',
    cdsStart => 'coding_start', exonEnds => 'exon_ends', exonStarts => 'exon_starts',
    strand => 'strand', txEnd => 'transcript_end', txStart => 'transcript_start',
  );
  my ( %header, %transcript_start_sites, %flank_exon_sites, %exon_sites);
  my $prn_count = 0;

  while(<$in_fh>)
  {
     chomp $_;
     my @fields = split(/\t/, $_);
     if ($. == 1)
     {
      map { $header{$fields[$_]} = $_ } (0..$#fields);
      next;
    }
    my %data = map { $_ => $fields[ $header{$_} ] }
      ( @{ $self->gene_fields_aref }, $self->all_names );

    # prepare basic gene data
    my %gene_data = map { $ucsc_table_lu{$_} => $data{$_} } keys %ucsc_table_lu;
    $gene_data{exon_ends}    = [ split(/\,/, $gene_data{exon_ends}) ];
    $gene_data{exon_starts}  = [ split(/\,/, $gene_data{exon_starts}) ];
    $gene_data{genome_track} = $self->genome_track_str;

    # prepare alternative names for gene
    my %alt_names = map { $_ => $data{$_} if exists $data{$_} } ( $self->all_names );

    my $gene = Seq::Gene->new( \%gene_data );
    $gene->set_alt_names( %alt_names );

    # get intronic flanking site annotations
    my @flank_exon_sites = $gene->get_flanking_sites();
    for my $site (@flank_exon_sites)
    {
      my $site_href = $site->as_href;
      $self->mongo_connection->_mongo_collection( $self->name )->insert( $site_href );
      # $gene_collection->insert( $site_href );

      if ($prn_count == 0)
      {
        print { $out_fh } "[" . encode_json( $site_href );
        $prn_count++;
      }
      else
      {
        print { $out_fh} "," . encode_json( $site_href );
        $prn_count++;
      }
      $flank_exon_sites{ $site->abs_pos }++;
    }

    # get exon annotations
    my @exon_sites = $gene->get_transcript_sites();
    for my $site (@exon_sites)
    {
      my $site_href = $site->as_href;
      $self->mongo_connection->_mongo_collection( $self->name )->insert( $site_href );
      # $gene_collection->insert( $site_href );

      if ($prn_count == 0)
      {
        print { $out_fh } "[" . encode_json( $site_href );
        $prn_count++;
      }
      else
      {
        print { $out_fh} "," . encode_json( $site_href );
        $prn_count++;
      }
      $exon_sites{ $site->abs_pos }++;
    }
    push @{ $transcript_start_sites{ $gene_data{transcript_start} } },
      $gene_data{transcript_end};
  }
  print { $out_fh } "]";
  return (\%exon_sites, \%flank_exon_sites, \%transcript_start_sites);
}


=head1 AUTHOR

Thomas Wingo, C<< <thomas.wingo at emory.edu> >>

=head1 BUGS

Please report any bugs or feature requests to C<bug-seq-build-genetrack at rt.cpan.org>, or through
the web interface at L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=Seq-Build-GeneTrack>.  I will be notified, and then you'll
automatically be notified of progress on your bug as I make changes.




=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc Seq::Build::GeneTrack


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

1; # End of Seq::Build::GeneTrack
