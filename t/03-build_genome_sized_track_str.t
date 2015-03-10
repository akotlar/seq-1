#!perl -T
use 5.10.0;
use strict;
use warnings;
use Test::More;
use File::Copy;
use Scalar::Util qw( blessed );
use Lingua::EN::Inflect qw( A PL_N );
use IO::Uncompress::Gunzip qw( $GunzipError );
use DDP;
use YAML qw( LoadFile );

plan tests => 20;

# set test genome
my $hg38_config_file = "hg38_gst_test.yml";

# setup testing enviroment
{
  copy ("./t/$hg38_config_file", "./sandbox/$hg38_config_file")
    or die "cannot copy ./t/$hg38_config_file to ./sandbox/$hg38_config_file $!";
  chdir("./sandbox");
}

# test the package's attributes and type constraints
my $package = "Seq::Build::GenomeSizedTrackStr";

# load package
use_ok($package) || die "$package cannot be loaded";

# check package extends Seq::Config::GenomeSizedTrack which is a Moose::Object 
check_isa( $package, ['Seq::Config::GenomeSizedTrack', 'Moose::Object'] );

# check package uses Moose
ok( $package->can('meta'), "$package has a meta() method" )
  or BAIL_OUT("$package does not have a meta() method.");

# check type constraints for attributes that should have Str values
for my $attr_name (qw( genome_seq ))
{
  my $attr = $package->meta->get_attribute($attr_name);
  ok( $attr->has_type_constraint, "$package $attr_name has a type constraint");
  is( $attr->type_constraint->name, 'Str', "$attr_name type is Str" );
}

# check obj creation
my $hg38_dat = LoadFile( $hg38_config_file );
my %hg38_genome_config;

for my $attr_href ( @{ $hg38_dat->{genome_sized_tracks} } )
{
  if ($attr_href->{type} eq "genome")
  {
    for my $attr ( keys %{ $attr_href })
    {
      $hg38_genome_config{ $attr } = $attr_href->{$attr};
    }
  }
}

$hg38_genome_config{genome_chrs} = $hg38_dat->{genome_chrs};

my $hg38_gst = Seq::Build::GenomeSizedTrackStr->new( \%hg38_genome_config );
ok ( ( $hg38_gst
      && (blessed $hg38_gst || !ref $hg38_gst)
      && $hg38_gst->isa($package) )
    , "$package obj created");


# make a genome string with single bases
{
  my @test_bases = qw( A C T G );
  my $test_str   = join("", @test_bases);
  for my $base (@test_bases)
  {
    $hg38_gst->add_seq($base);
  }
  is($hg38_gst->genome_seq, $test_str, 'build str seq from bases');

  # get genome length
  is( $hg38_gst->length_genome_seq, 4, 'got length of string genome');

  # clear genome
  $hg38_gst->clear_genome_seq;
  is( $hg38_gst->genome_seq, '', 'cleared string genome');
}

# make a genome string with large strings of bases
{
  my @test_base_rows = qw( AAAAAAA CCCCCC TTTTTT GGGGGGG );
  my $test_str       = join("", @test_base_rows);
  for my $base_row (@test_base_rows)
  {
    $hg38_gst->add_seq( $base_row );
  }
  is($hg38_gst->genome_seq, $test_str, 'build str seq from rows of bases');
}

# get a string of DNA bases from an arbitrary locaiton
{
  # clear genome sequence
  $hg38_gst->clear_genome_seq;

  my @test_bases = qw( A C T G C A G T );
  my (@obs_bases, @exp_bases);
  for my $base (@test_bases)
  {
    $hg38_gst->add_seq( $base );
  }

  for (my $i=$#test_bases; $i >= 0; $i--)
  {
    push @exp_bases, $test_bases[$i];
    push @obs_bases, $hg38_gst->get_base( $i, 1 );
  }
  is_deeply(\@obs_bases, \@exp_bases, 'substring out correct base');
}

# build the genome
{
  my %chr_lens = ( );
  $hg38_gst->clear_genome_seq;
  $hg38_gst->build_genome;

  my $exp_genome_seq = '';
  my $local_dir   = File::Spec->canonpath( $hg38_genome_config{local_dir} );
  for my $chr_file (@{ $hg38_genome_config{local_files} })
  {
    my $local_file = File::Spec->catfile( $local_dir, $chr_file );
    my $fh = new IO::Uncompress::Gunzip $local_file ||
      die "gzip failed: $GunzipError\n";

    ( my $chr = $chr_file ) =~ s/\.fa\.gz//;
    $chr_lens{ $chr } = length $exp_genome_seq;

    while (<$fh>)
    {
      chomp $_;
      next if $_ =~ m/\A>/;
      $exp_genome_seq .= $1 if ( $_ =~ m/(\A[ATCGNatcgn]+)\Z/);
    }
    $chr_lens{ 'genome' } = length $exp_genome_seq;
  }
  is( $hg38_gst->genome_seq, $exp_genome_seq, 'build_genome() ok' );
  
  my (@exp, @obs);
  for my $chr (@{ $hg38_genome_config{genome_chrs} })
  {
    push @obs, $hg38_gst->get_abs_pos( $chr, 0 );
    push @exp, $chr_lens{$chr};
  }

  push @obs, $hg38_gst->length_genome_seq;
  push @exp, $chr_lens{genome};

  is_deeply(\@obs, \@exp, 'get_abs_pos() index the genome');
}

sub does_role {
    my $package = shift;
    my $role    = shift;

    local $Test::Builder::Level = $Test::Builder::Level + 1;

    ok( $package->meta->does_role($role), "$package does the $role role" );
}

sub check_isa {
    my $class   = shift;
    my $parents = shift;

    local $Test::Builder::Level = $Test::Builder::Level + 1;

    my @isa = $class->meta->linearized_isa;
    shift @isa;    # returns $class as the first entry

    my $count = scalar @{$parents};
    my $noun = PL_N( 'parent', $count );

    is( scalar @isa, $count, "$class has $count $noun" );

    for ( my $i = 0; $i < @{$parents}; $i++ ) {
        is( $isa[$i], $parents->[$i], "parent[$i] is $parents->[$i]" );
    }
}

sub has_ro_attr {
    my $class = shift;
    my $name  = shift;

    local $Test::Builder::Level = $Test::Builder::Level + 1;

    my $articled = A($name);
    ok(
        $class->meta->has_attribute($name),
        "$class has $articled attribute"
    );

    my $attr = $class->meta->get_attribute($name);

    is(
        $attr->get_read_method, $name,
        "$name attribute has a reader accessor - $name()"
    );
    is(
        $attr->get_write_method, undef,
        "$name attribute does not have a writer"
    );
}

sub has_rw_attr {
    my $class      = shift;
    my $name       = shift;
    my $overridden = shift;

    local $Test::Builder::Level = $Test::Builder::Level + 1;

    my $articled = $overridden ? "an overridden $name" : A($name);
    ok(
        $class->meta->has_attribute($name),
        "$class has $articled attribute"
    );

    my $attr = $class->meta->get_attribute($name);

    is(
        $attr->get_read_method, $name,
        "$name attribute has a reader accessor - $name()"
    );
    is(
        $attr->get_write_method, $name,
        "$name attribute has a writer accessor - $name()"
    );
}
