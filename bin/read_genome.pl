#!/usr/bin/env perl

# Name:           read_genome.pl
# Description:
#   Input:
#     - chromosome and positions
#     - yaml configuration file
#     - location of the database
#   Output:
#     - tab delimited genomic sequence and indication of features present at
#       particular absolute positions in the genome
#
# Date Created:   Tue Sep 21 13:36:45 2014
# Date Modified:  2015-03-19
# By:             TS Wingo
#
# TODO:
#   - remove relative library position
#

use lib './lib';
use autodie;
use Cpanel::JSON::XS;
use File::Spec;
use IO::File;
use Getopt::Long;
use Modern::Perl qw/ 2013 /;
use Pod::Usage;
use YAML::XS qw/ LoadFile /;
use Seq::GenomeSizedTrackChar;
use Time::localtime;
use Type::Params qw/ compile /;
use Types::Standard qw/ FileHandle slurpy Str ArrayRef Num /;
use DDP;

my (
  $chr_wanted, $pos_from,    $pos_to, $db_location, $yaml_config,
  $verbose,    $client,      $db,     $gan_db,      $snp_db,
  $dbsnp_name, $dbgene_name, $help,   $genome_length
);
my (%tracks);

#
# usage
#
GetOptions(
  'c|chr=s'      => \$chr_wanted,
  'f|from=n'     => \$pos_from,
  't|to=n'       => \$pos_to,
  'c|config=s'   => \$yaml_config,
  'l|location=s' => \$db_location,
  'v|verbose'    => \$verbose,
  'h|help'       => \$help,
);

if ($help) {
  Pod::Usage::pod2usage(1);
  exit;
}

unless ( defined $pos_from
  and defined $pos_to
  and defined $yaml_config
  and defined $db_location )
{
  Pod::Usage::pod2usage();
}

# clean up position
$pos_from =~ s/\_|\,//g;
$pos_to =~ s/\_|\,//g;

# sanity check position
if ( $pos_from >= $pos_to ) {
  say "Error: 'from' ('$pos_from') is greater than 'to' ('$pos_to')\n";
  exit;
}

my $now_timestamp = sprintf(
  "%d-%02d-%02d-%02d%02d%02d",
  ( localtime->year + 1900 ),
  ( localtime->mon + 1 ),
  localtime->mday, localtime->hour, localtime->min, localtime->sec
);
my $out_fh = IO::File->new( "fa.$now_timestamp.seq", 'w' );

# load configuration file
my $config_data = LoadFile($yaml_config);

# genome assembly
my $assembly //= $config_data->{genome_name};

# db location
$db_location = File::Spec->canonpath($db_location);

# index directory
my $index_dir //= $config_data->{genome_index_dir};
$index_dir = File::Spec->canonpath($index_dir);

#  make genome sized objects
for my $gst ( @{ $config_data->{genome_sized_tracks} } ) {
  # naming convetion is 'name.type.idx' and 'name.type.yml' for the index and
  # the chr_len offsets, respectively
  my $idx_file = join( ".", $gst->{name}, $gst->{type}, 'idx' );
  my $yml_file = join( ".", $gst->{name}, $gst->{type}, 'yml' );
  my $full_path_idx = File::Spec->catfile( $db_location, $index_dir, $idx_file );
  my $full_path_yml = File::Spec->catfile( $db_location, $index_dir, $yml_file );
  my $idx_fh = new IO::File->new( $full_path_idx, 'r' )
    or die "cannot open $full_path_idx";

  binmode $idx_fh;
  my $gst_dat;
  $genome_length = -s $full_path_idx;
  read $idx_fh, $gst_dat, $genome_length;
  my $chr_len_href = LoadFile($full_path_yml);

  my %gst_config = %$gst;
  $gst_config{genome_chrs}   = $config_data->{genome_chrs};
  $gst_config{genome_length} = -s $full_path_idx;
  $gst_config{chr_len}       = $chr_len_href;

  #p %gst_config;
  $gst_config{char_seq} = \$gst_dat;

  push @{ $tracks{ $gst->{type} } }, Seq::GenomeSizedTrackChar->new( \%gst_config );
}

# print header
my @header = qw( abs_pos chr pos base_code base gan gene exon snp );
for my $score_track ( @{ $tracks{score} } ) {
  push @header, 'score';
}
say join( "\t", @header );

my @seq;
for ( my $i = $pos_from; $i < $pos_to; $i++ ) {
  my $zero_idx = $i;
  my $one_idx  = $i + 1;

  my $genome = $tracks{genome}[0];

  my $base_code = $genome->get_base($zero_idx);
  my $chr       = get_chr($zero_idx);
  my $rel_pos   = $i + 1 - $genome->get_abs_pos( $chr, 1 );

  my $base = $genome->get_idx_base($base_code);
  my $gan  = ( $genome->get_idx_in_gan($base_code) ) ? 1 : 0;
  my $gene = ( $genome->get_idx_in_gene($base_code) ) ? 1 : 0;
  my $exon = ( $genome->get_idx_in_exon($base_code) ) ? 1 : 0;
  my $snp  = ( $genome->get_idx_in_snp($base_code) ) ? 1 : 0;

  my @site_scores;
  for my $score_track ( @{ $tracks{score} } ) {
    push @site_scores, $score_track->get_score($zero_idx);
  }

  say join( "\t",
    $i, $chr, $rel_pos, $base_code, $base, $gan, $gene, $exon, $snp, @site_scores );
  push @seq, $base;
}

# print final sequence captured as a fa - for blat or something
Print_fa( $out_fh, \@seq );

#
# subroutines
#
sub Print_fa {
  state $check = compile( FileHandle, ArrayRef [Str] );
  my ( $fh, $seq_aref ) = $check->(@_);

  for ( my $i = 0; $i < @$seq_aref; $i++ ) {
    print $fh "\n" if ( $i % 80 == 0 );
    print $fh $seq_aref->[$i];
  }
}

sub get_chr {
  state $check = compile(Num);
  my ($pos)  = $check->(@_);
  my @chrs   = @{ $config_data->{genome_chrs} };
  my $genome = $tracks{genome}[0];
  for my $i ( 0 .. scalar @chrs ) {
    my $chr      = $chrs[$i];
    my $chr_len  = $genome->get_abs_pos( $chr, 1 );
    my $next_chr = $chrs[ $i + 1 ];
    if ($next_chr) {
      my $next_chr_len = $genome->get_abs_pos( $next_chr, 1 );
      if ( $pos < $next_chr_len && $pos >= $chr_len ) {
        return $chr;
      }
    }
    else {
      if ( $pos < $genome_length && $pos >= $chr_len ) {
        return $chr;
      }
    }

    #say "$pos < $next_chr_len && $pos >= $chr_len";

  }
}

__END__

=head1 NAME

read_genome - reads binary genome

=head1 SYNOPSIS

read_genome --from --to --config --locaiton

=head1 DESCRIPTION

C<read_genome> takes a yaml configuration file and reads the binary genome
specified by that file. The binary genome is created by the Seq package.

=head1 OPTIONS

=over 8

=item B<-f>, B<--from>

From: absolute position (0-indexed) to start reading the genome.

=item B<-t>, B<--to>

To: absolute position (0-indexed) to stop reading the genome.

=item B<-c>, B<--config>

Config: A YAML genome assembly configuration file that specifies the various
tracks and data associated with the assembly. This is the same file that is
used by the Seq Package to build the binary genome without any alteration.

=item B<-l>, B<--location>

Location: This is the base directory that will be added to the location
information in the YAML configuration file that has a key specifying the
location of the binary index.

=back

=head1 AUTHOR

Thomas Wingo

=head1 SEE ALSO

Seq Package

=cut
