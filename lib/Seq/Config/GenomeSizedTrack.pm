package Seq::Config::GenomeSizedTrack;

use 5.10.0;
use Carp qw( confess );
use Moose;
use Moose::Util::TypeConstraints;
use namespace::autoclean;
use Scalar::Util qw( reftype );

enum GenomeSizedTrackType => [ 'genome', 'score', ];

=head1 NAME

Config::GenomeSizedTrack - The great new Config::GenomeSizedTrack!

=head1 VERSION

Version 0.01

=cut

our $VERSION = '0.01';
my (%idx_codes, %idx_base, %idx_in_gan, %idx_in_gene, %idx_in_exon, %idx_in_snp);
{
  my @bases      = qw( A C G T N );
  my @annotation = qw( 0 1 );
  my @in_exon    = qw( 0 1 );
  my @in_gene    = qw( 0 1 );
  my @in_snp     = qw( 0 1 );
  my @char       = ( 0 .. 255 );
  my $i          = 0;

  foreach my $base (@bases)
  {
    foreach my $gan (@annotation)
    {
      foreach my $gene (@in_gene)
      {
        foreach my $exon (@in_exon)
        {
          foreach my $snp (@in_snp)
          {
            my $code = $char[$i];
            $i++;
            $idx_codes{$base}{$gan}{$gene}{$exon}{$snp} = $code;
            $idx_base{$code}    = $base;
            $idx_in_gan{$code}  = $base if $gan;
            $idx_in_gene{$code} = $base if $gene;
            $idx_in_exon{$code} = $base if $exon;
            $idx_in_snp{$code}  = $base if $snp;
          }
        }
      }
    }
  }
}

# 
# basic genome characteristics
#
has name => ( is => 'ro', isa => 'Str', required => 1, );
has type => ( is => 'ro', isa => 'GenomeSizedTrackType', required => 1, );
has genome_chrs => (
  is => 'ro',
  isa => 'ArrayRef[Str]',
  traits => ['Array'],
  required => 1,
);

#
# directory and file information
#
has genome_index_dir => (
  is => 'ro',
  isa => 'Str',
);
has local_dir => ( is => 'ro', isa => 'Str', );
has local_files => (
  is => 'ro',
  isa => 'ArrayRef[Str]',
  traits => ['Array'],
);
has remote_dir => ( is => 'ro', isa => 'Str' );
has remote_files => (
  is => 'ro',
  isa => 'ArrayRef[Str]',
  traits => ['Array'],
);

# 
# for processing scripts
#
has proc_init_cmds => (
  is => 'ro',
  isa => 'ArrayRef[Str]',
  traits => ['Array'],
);
has proc_chrs_cmds => (
  is => 'ro',
  isa => 'ArrayRef[Str]',
  traits => ['Array'],
);
has proc_clean_cmds => (
  is => 'ro',
  isa => 'ArrayRef[Str]',
  traits => ['Array'],
);

=head1 SYNOPSIS

Quick summary of what the module does.

Perhaps a little code snippet.

    use Config::GenomeSizedTrack;

    my $foo = Config::GenomeSizedTrack->new();
    ...

=head1 METHODS

=head2 get_idx_code

=cut

sub get_idx_code {
  my $self = shift;
  my ($base, $in_gan, $in_gene, $in_exon, $in_snp) = @_;

  confess "get_idx_code() expects base, in_gan, in_gene, in_exon, and in_snp"
    unless $base =~ m/[ACGTN]/
      and defined $in_gan 
      and defined $in_gene 
      and defined $in_exon 
      and defined $in_snp;

  my $code //= $idx_codes{$base}{$in_gan}{$in_gene}{$in_exon}{$in_snp};
  return $code;
}

sub get_idx_base {
  shift;
  my $base //= $idx_base{$_};
  return $base;
}

sub get_idx_in_gan {
  shift;
  my $code //= $idx_in_gan{$_};
  return $code;
}

sub get_idx_in_gene {
  shift;
  my $code //= $idx_in_gene{$_};
  return $code;
}

sub get_idx_in_exon {
  shift;
  my $code //= $idx_in_exon{$_};
  return $code;
}

sub get_idx_in_snp {
  shift;
  my $code //= $idx_in_snp{$_};
  return $code;
}
=head1 AUTHOR

Thomas Wingo, C<< <thomas.wingo at emory.edu> >>

=head1 BUGS

Please report any bugs or feature requests to C<bug-config-GenomeSizedTracktrack at rt.cpan.org>, or through
the web interface at L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=Config-GenomeSizedTrack>.  I will be notified, and then you'll
automatically be notified of progress on your bug as I make changes.




=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc Config::GenomeSizedTrack


You can also look for information at:

=over 4

=item * RT: CPAN's request tracker (report bugs here)

L<http://rt.cpan.org/NoAuth/Bugs.html?Dist=Config-GenomeSizedTrack>

=item * AnnoCPAN: Annotated CPAN documentation

L<http://annocpan.org/dist/Config-GenomeSizedTrack>

=item * CPAN Ratings

L<http://cpanratings.perl.org/d/Config-GenomeSizedTrack>

=item * Search CPAN

L<http://search.cpan.org/dist/Config-GenomeSizedTrack/>

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

1; # End of Config::GenomeSizedTrack
