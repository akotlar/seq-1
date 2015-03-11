package Seq::Build::GenomeSizedTrackStr;

use 5.10.0;
use Carp;
use File::Path;
use File::Spec;
use Moose;
use namespace::autoclean;
extends 'Seq::Config::GenomeSizedTrack';
with 'Seq::IO';

=head1 NAME

Seq::Build::GenomeSizedTrackStr - The great new Seq::BuildGenomeSizedTrackStr!

=head1 VERSION

Version 0.01

=cut

my %chr_lens = ( );

# str_seq stores a string in a single scalar
has genome_seq => (
  is => 'rw',
  writer => undef,
  default => sub { '' },
  isa => 'Str',
  traits => ['String'],
  handles => {
    add_seq => 'append',
    clear_genome_seq => 'clear',
    length_genome_seq => 'length',
    get_base => 'substr',
  },
  lazy => 1,
);

=head1 SYNOPSIS

=head1 METHODS

=head2 get_abs_pos

Returns an absolute position for a given chr and position.

=cut

sub get_abs_pos {
  my ($self, $chr, $pos ) = @_;
  confess "expected chromosome and position" unless defined $chr and defined $pos;
  confess "expected position to be >= 1" unless $pos >= 1;
  confess "position outside of genome, which is " . $self->length_genome_seq  
    unless $pos < $self->length_genome_seq;
  my $abs_pos //= $chr_lens{$chr} + $pos - 1;
  return $abs_pos;
}

=head2 _build_genome

=cut

sub build_genome {
  my $self = shift;
  my $local_dir   = File::Spec->canonpath( $self->local_dir );
  my @local_files = $self->all_local_files;
  my @genome_chrs = $self->all_genome_chrs;

  for (my $i = 0; $i < @local_files; $i++)
  {
    my $file       = $local_files[$i];
    my $chr        = $genome_chrs[$i];

    my @file_fields = split(/\./, $file);
    croak "expected chromosomes and sequence files to be in the"
           . " same order but found $file with $chr\n"
           unless $chr eq $file_fields[0];

    my $local_file  = File::Spec->catfile( $local_dir, $file );
    my $in_fh       = $self->get_read_fh( $local_file );
    $chr_lens{$chr} = $self->length_genome_seq;
    while ( my $line = $in_fh->getline() )
    {
      chomp $line;
      $line =~ s/\s+//g;
      next if ( $line =~ m/\A>/ );
      if ( $line =~ m/(\A[ATCGNatcgn]+)\Z/)
      {
        $self->add_seq( uc $1 );
      }
      else
      {
        croak join("\n", "ERROR: Unexpected Non-Base Character.", 
          "\tfile: $file ",
          "\tline: $.",
          "\tsequence: $line");
      }
    }
  }
}


__PACKAGE__->meta->make_immutable;

1; # End of Seq::Build::GenomeSizedTrackStr
