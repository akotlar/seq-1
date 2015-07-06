use 5.10.0;
use strict;
use warnings;
use Carp qw/ croak /;

# TODO: Clarify whether gan / $in_gan refers to knownGene annotations.
# NOTE: Alex, gan refers to any SparseTrack gene annoation.

package Seq::Config::GenomeSizedTrack;
# ABSTRACT: Configure a genome sized track
# VERSION

=head1 DESCRIPTION

  @class B<Seq::Config::GenomeSizedTrack>

  A genome sized track is one that contains a {Char} for every position in the
  genome. There are three different types that are enumerated below.

  This class provides getters and setters for the management of these hashes.

  This class can be consumed directly:

    @example Seq::Config::GenomeSizedTrack->new($gst)

  Or as a Type Constraint:

    @example has => some_property ( isa => 'ArrayRef[Seq::Config::GenomeSizedTrack]' )

Used in:

=for :list
* @class Seq::Assembly
    Seq::Assembly is used in @class Seq::Annotate, which is used in @class Seq.pm

Extended in:

=for :list
* @class Seq::Build::GenomeSizedTrackStr
* @class Seq::GenomeSizedTrackChar
* @class Seq::Fetch::Sql

=cut

use Moose 2;
use Moose::Util::TypeConstraints;
use MooseX::Types::Path::Tiny qw/ Path AbsFile AbsPath AbsPaths/;

use namespace::autoclean;
use Scalar::Util qw/ reftype /;

use DDP; # for debugging

=type GenomeSizedTrackType

GenomeSizedTrack are binary encoded data that is loaded at runtime in memory.
There are three different types:

=for :list

1. genome
  A binary representation of a reference genome assembly that encodes for each
  position in the genome the nucleotide and the presence of a SparseTrack site
  (often a SNP) and whther the base is within a gene region or exon. Only one
  GenomeSizedTrackType may be defined for a given assembly.

2. score
  Any WigFix format score. The underlying value is a {Char}, values 0-255,
  necessitating the user to define a mapping function when the genome is built
  to store the values. See C<Seq::Config::GenomeSizedTrack::BUILDARGS> mapping
  functions for PhastCons and PhyloP scores.

  Any number of score type GenomeSizedTrackType may be defined on any one
  assembly; however, this is practically limited by the available memory since
  all scores will be loaded at runtime.

3. cadd
  This is really a special purpose track for the CADD score, see
  L<http://cadd.gs.washington.edu>. The format is an extended bed format:
  `chr start stop score_1 score_2 score_3`.

genome & score type file format:
=for :list

1. A `.idx` file
  Binary {Char} data for each at each position in the genome. The file should be
  the exact size of the genome.

2. A `.yml` file
  Chromosome offset data in YAML format. Needed to convert relative genomic
  coordinates to absolute coordinates needed to extract data from the binary
  data. E.g., {chr# : first_position_exclusive_of_this_chr}.

cadd type file format:

  1. N number of files, representating N possible genome-wide states. In the
  case of CADD scores, N=3, as each SNP can have up to three transition states
  (4 based - 1 reference base)

  See use in L<Seq::Annotate>

# TODO: Check if Seq::Config::GenomeSizedTrack::BUILDARGS makes sense as a
#       representation of "BUILDARGS method of this class"
# TODO: Clarify whether offset is inclusive or exclusive, and triple check that
#       offset is used because the pos given in the snpfile is relative to the
#       chromosome, and that is used for seeking.
=cut

enum GenomeSizedTrackType => [ 'genome', 'score', 'cadd' ];

# TODO: This section that describes the encoding of the base could be a bit
#       clearer, I think.
# The basic notion might need to be introduced - i.e., to save time we encode
# the genome as a binary string that hold different values depending on whether
# there are certain features at the particular position. To do this, we
# arbitrarily set values for the nucleotides and features. The features are:
# 1) annotated gene, 2) exon, 3) within a gene boundary, and 4) snp site.
# The exact choice of the values (i.e., factors of 2) simplifies setting the
# encoded values since we can use a bit-wise OR opperator wihtout needing to
# check the value is already set.

my ( @idx_codes, @idx_base, @idx_in_gan, @idx_in_gene, @idx_in_exon, @idx_in_snp );

=variable {Hash} @private %base_char_2_txt

  Provides {Int} values for each possible base type.

  @see Seq::Site::Annotation @type non_missing_base_types

=cut

my %base_char_2_txt = ( '0' => 'N', '1' => 'A', '2' => 'C', '3' => 'G', '4' => 'T' );

# feature values representing whether something is in an annotated gene, in an
# exon, in a gene, or in a snp combinations of these values will reveal
# combinations of propeties

my @in_gan  = qw/ 0 8 /; # is gene annotated
my @in_exon = qw/ 0 16 /;
my @in_gene = qw/ 0 32 /;
my @in_snp  = qw/ 0 64 /;

# we will use 0 to indicate absence and undef to indicate an error
# each position in the genome can take on a max value of 255 {Char}
# the maximum sum we allow is 255, although the current program uses only 116
for ( my $i = 0; $i < 256; $i++ ) {
  $idx_codes[$i] = $idx_base[$i] = $idx_in_gan[$i] = $idx_in_gene[$i] =
    $idx_in_exon[$i] = $idx_in_snp[$i] = undef;
}

# fill properties
# iterate over all of the keys in %base_char_2_txt @values 0...4
foreach my $base_char ( keys %base_char_2_txt ) {
  #iterate over @in_snp elements @values 0,64
  foreach my $snp (@in_snp) {
    #iterate over @in_exon elements @values 0,16
    foreach my $gene (@in_gene) {
      #iterate over @in_gene elements @values 0,32
      foreach my $exon (@in_exon) {
        #iterate over @in_snp elements @values 0,8
        foreach my $gan (@in_gan) {
          #$base_char gets duck types as an {Int}
          my $char_code = $base_char + $gan + $gene + $exon + $snp;

          my $txt_base = $base_char_2_txt{$base_char};
          $idx_base[$char_code] = $txt_base;

          # equivalent to testing ($gan) ? 1 : 0 is !!$gan
          # these values are combinations of the iterated values
          # and a 0 feature value always corresponds to
          $idx_in_gan[$char_code]  = ($gan)  ? 1 : 0;
          $idx_in_gene[$char_code] = ($gene) ? 1 : 0;
          $idx_in_exon[$char_code] = ($exon) ? 1 : 0;
          $idx_in_snp[$char_code]  = ($snp)  ? 1 : 0;

          # @example:
          # 0 + 0 + 0 + 64 == 'N',no gan, not in a gene, not in an exon, is a snp
        }
      }
    }
  }
}

=property @public @required {Str} name

  The feature name. This is defined directly in the input config file.

  @example:
  =for :list
  * PhastCons
  * PhyloP
  * CADD

=cut

has name => ( is => 'ro', isa => 'Str', required => 1, );

=property @public @required {GenomeSizedTrackType<Str>} type

  The type of feature

  @values:

  =for :list
  * genome
    Only one feature of this type may exist
  * score
    The 1 binary, 1 offset file format. @example: PhyloP
  * cadd
    The N binary file format @example: CADD

=cut

has type => ( is => 'ro', isa => 'GenomeSizedTrackType', required => 1, );

=property {ArrayRef<Str>} genome_chrs

  An array reference holding the list of chromosomes in the genome assembly.
  The list of chromosomes is supplied by the configuration file.

Used in:

=for :list
* bin/make_fake_genome.pl
* bin/read_genome.pl
* bin/run_all_build.pl
* @class Seq::Annotate
* @class Seq::Assembly
* @class Seq::Build::GenomeSizedTrackStr
* @class Seq::Build
* @class Seq::Fetch

=cut

=method all_genome_chrs

  Returns all of the elements of the @property {ArrayRef<str>} C<genome_chrs>
  as an array (not an array reference).
  $self->all_genome_chrs

=cut

has genome_chrs => (
  is       => 'ro',
  isa      => 'ArrayRef[Str]',
  traits   => ['Array'],
  required => 1,
  handles  => { all_genome_chrs => 'elements', },
);

has next_chr => (
  is      => 'ro',
  isa     => 'HashRef',
  traits  => ['Hash'],
  lazy    => 1,
  builder => '_build_next_chr',
  handles => { get_next_chr => 'get', },
);

# file stuff
has genome_index_dir => ( is => 'ro', isa => Path, coerce => 1, );

# I favor removing genome_raw_dir and requiring the local_dir only be used
has genome_raw_dir   => ( is => 'ro', isa => Path, coerce => 1, );
has local_dir        => ( is => 'ro', isa => Path, coerce => 1, );

has genome_str_file => (
  is => 'ro',
  isa => AbsPath,
  builder => '_build_genome_str_file',
  lazy => 1,
  coerce => 1,
);
has genome_bin_file => (
  is => 'ro',
  isa => AbsPath,
  builder => '_build_genome_bin_file',
  lazy => 1,
  coerce => 1,
);

sub _build_genome_str_file {
  my $self = shift;
  my $ext = 'str.dat';
  my $base_dir = $self->genome_index_dir;
  my $file = join ".", $self->name, $self->type, $ext;
  return $base_dir->child($file);
}

sub _build_genome_bin_file {
  my $self = shift;
  my $ext = 'idx';
  my $base_dir = $self->genome_index_dir;
  my $file = join ".", $self->name, $self->type, $ext;
  return $base_dir->child($file);
}

# this is the list of things passed to the class
has local_files => (
  is      => 'ro',
  isa     => 'ArrayRef[Str]',
  traits  => ['Array'],
  handles => { all_local_files  => 'elements', },
);

has raw_genome_files => (
  is => 'ro',
  isa => AbsPaths,
  builder => '_build_raw_genome_files',
  traits  => ['Array'],
  handles => { all_raw_genome_files  => 'elements', },
  coerce  => 1,
);

sub _build_raw_genome_files {
  my $self = shift;
  my @array;
  my $base_dir = $self->local_dir;
  for my $file ( $self->all_local_files ) {
    push @array, $base_dir->child($file);
  }
  return \@array;
}

has remote_dir => ( is => 'ro', isa => 'Str' );
has remote_files => (
  is     => 'ro',
  isa    => 'ArrayRef[Str]',
  traits => ['Array'],
);

# for conservation scores
has score_min => (
  is  => 'ro',
  isa => 'Num'
);

has score_max => (
  is  => 'ro',
  isa => 'Num',
);

=property @public score_R

  The number of radians the raw score will get divided into. This MUST NOT
  EXCEED the max R found in genome_scorer.c

=cut

has score_R => (
  is      => 'ro',
  isa     => 'Num',
  default => 255
);

=property @private {Float} _score_beta

  Standardized value for a particular feature type, such as CADD, PhyloP, or
  PhastCons.

  Calculated in the builder @function _build_score_beta, lazily, meaning only
  when $self->_score_beta is called.

=cut

has _score_beta => (
  is      => 'ro',
  isa     => 'Num',
  lazy    => 1,
  builder => '_build_score_beta',
);

has _score_lu => (
  is      => 'ro',
  isa     => 'HashRef',
  traits  => ['Hash'],
  lazy    => 1,
  handles => { get_score_lu => 'get', },
  builder => '_build_score_lu',
);

=method @private _build_score_lu

  Precompute all possible scores, for efficient lookup

@returns {HashRef}
  The score look up table. Keys are 0-255 (i.e., {Char} values), and the values
  are scores.

# TODO: Check if it's correct to say "Radian" values.
=cut

sub _build_score_lu {
  my $self = shift;

  # NOTE: score_R may be lower than 255 but it will _never_ be higher because it
  #       is checked in BUILD TO BE WRITTEN
  my %score_lu =
    map { $_ => ( ( ( $_ - 1 ) / $self->_score_beta ) + $self->score_min ) }
    ( 1 .. $self->score_R );
  $score_lu{'0'} = 'NA';

  return \%score_lu;
}

sub _build_score_beta {
  my $self = shift;
  return ( ( $self->score_R - 1 ) / ( $self->score_max - $self->score_min ) );
}

sub _build_next_chr {
  my $self = shift;

  my %next_chrs;
  my @chrs = $self->all_genome_chrs;
  for my $i ( 0 .. $#chrs ) {
    if ( defined $chrs[ $i + 1 ] ) {
      $next_chrs{ $chrs[$i] } = $chrs[ $i + 1 ];
    }
  }
  return \%next_chrs;
}

sub get_idx_base {
  my ( $self, $char ) = @_;
  return $idx_base[$char];
}

sub get_idx_in_gan {
  my ( $self, $char ) = @_;
  return $idx_in_gan[$char];
}

sub get_idx_in_gene {
  my ( $self, $char ) = @_;
  return $idx_in_gene[$char];
}

sub get_idx_in_exon {
  my ( $self, $char ) = @_;
  return $idx_in_exon[$char];
}

=method @public get_idx_in_snp

  Takes an integer code representing the features at a genomic position.
  Returns a 1 if this position is a snp, or 0 if not

  $self->get_idx_in_snp($site_code)

  See the anonymous routine ~line 100 that fills $idx_in_snp.

Used in @class Seq::Annotate

@requires @private {Array<Bool>} $idx_in_snp

@param {Int} $char

@returns {Bool} @values 0, 1

=cut

sub get_idx_in_snp {
  my ( $self, $char ) = @_;
  return $idx_in_snp[$char];
}

=method @public get_idx_in_snp

  @see get_idx_in_snp

=cut

sub in_gan_val {
  my $self = @_;
  return $in_gan[1];
}

=method @public get_idx_in_snp

  @see get_idx_in_snp

=cut

sub in_exon_val {
  my $self = @_;
  return $in_exon[1];
}

=method @public get_idx_in_snp

  @see get_idx_in_snp

=cut

sub in_gene_val {
  my $self = @_;
  return $in_gene[1];
}

=method @public get_idx_in_snp

  @see get_idx_in_snp

=cut

sub in_snp_val {
  my $self = @_;
  return $in_snp[1];
}

=constructor

  Overrides BUILDARGS construction function to set default values for (if not set):

  =for :list
  * @property {Int} score_R
  * @property {Int} score_min
  * @property {Int} score_max

@requires

=for :list
* @property {Str} type
* @property {Str} name

@returns {$class->SUPER::BUILDARGS}

=cut

# TODO: Alex, could you clarify what you meant here?
# TODO: move away from this in favor of read only accesssor

sub BUILD {
  my $self = shift;

  return if ( !( $self->type eq "score" or $self->type eq "cadd" ) );

  $self->_validate_feature_score_range();
}

# TODO: consider changing the min score_R to 5
sub _validate_feature_score_range {
  my $self = shift;

  # TODO: set range for genome_scorer.c and Seq package from single config.
  unless ( $self->score_R < 256 and $self->score_R >= 5 ) {
    my $err_msg =
      "FATAL ERROR: We believe score_R must be within 5 - 255, check genome_scorer.c for current range";
    $self->_logger->error($err_msg);
    croak $err_msg;
  }

  if ( $self->score_min == 0 and $self->score_max == 0 ) {
    my $wrn_msg = "score_min and score_max are 0";
    $self->_logger->warn($wrn_msg);
    warn $wrn_msg;
  }
}

# NOTE: Alex, I don't think you can use around for BUILDARGS.
# TODO: Documentation: decide whether this is equivalent to around, if so, maybe
#       switch because better documented
sub BUILDARGS {
  my $class = shift;
  my $href  = $_[0];
  if ( scalar @_ > 1 || reftype($href) ne "HASH" ) {
    confess "Error: $class expects hash reference.\n";
  }
  else {
    if ( $href->{type} eq "score" ) {
      if ( $href->{name} eq "phastCons" ) {
        $href->{score_min} = 0;
        $href->{score_max} = 1;
      }
      elsif ( $href->{name} eq "phyloP" ) {
        $href->{score_min} = -30;
        $href->{score_max} = 30;
      }
    }
    elsif ( $href->{type} eq "cadd" ) {
      $href->{score_min} = 0;
      $href->{score_max} = 85;
    }
    return $class->SUPER::BUILDARGS($href);
  }
}

__PACKAGE__->meta->make_immutable;

1;
