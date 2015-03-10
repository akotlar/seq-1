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

plan tests => 19;

# set test genome
my $hg38_config_file = "hg38_gst_test.yml";

# setup testing enviroment
{
  copy ("./t/$hg38_config_file", "./sandbox/$hg38_config_file")
    or die "cannot copy ./t/$hg38_config_file to ./sandbox/$hg38_config_file $!";
  chdir("./sandbox");
}

# test the package's attributes and type constraints
my $package = "Seq::Build::GenomeSizedTrackChar";

# load package
use_ok( $package ) || die "$package cannot be loaded";

# check is a moose object
check_isa( $package, ['Seq::Config::GenomeSizedTrack', 'Moose::Object']  );

# check package uses Moose
ok( $package->can('meta'), "$package has a meta() method" )
  or BAIL_OUT("$package does not have a meta() method.");

# check length constraints for attributes that should have Int values
for my $attr_name (qw( length ))
{
  my $attr = $package->meta->get_attribute($attr_name);
  ok( $attr->has_type_constraint, "$package $attr_name has a type constraint");
  is( $attr->type_constraint->name, 'Int', "$attr_name type is Int" );
}

# check type constraints for attributes that should have ScalarRef values
for my $attr_name (qw( char_seq ))
{
  my $attr = $package->meta->get_attribute($attr_name);
  ok( $attr->has_type_constraint, "$package $attr_name has a type constraint");
  is( $attr->type_constraint->name, 'ScalarRef',
    "$attr_name type is ScalarRef" );
}

# check type constraints for attributes that should have HashRef[Str] values
for my $attr_name (qw( chr_len ))
{
  my $attr = $package->meta->get_attribute($attr_name);
  ok( $attr->has_type_constraint, "$package $attr_name has a type constraint");
  is( $attr->type_constraint->name, 'HashRef[Str]',
    "$attr_name type is HashRef[Str]" );
}

# check type constraints for attributes that should have CodeRef values
for my $attr_name (qw( char2score score2char ))
{
  my $attr = $package->meta->get_attribute($attr_name);
  ok( $attr->has_type_constraint, "$package $attr_name has a type constraint");
  is( $attr->type_constraint->name, 'CodeRef', "$attr_name type is CodeRef" );
}

# for check obj creation
my $hg38_dat = LoadFile( $hg38_config_file );
my (%hg38_genome_config, %chr_lens);

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

# next bit to get genome length
my $test_genome_seq = '';
my $local_dir   = File::Spec->canonpath( $hg38_genome_config{local_dir} );
for my $chr_file (@{ $hg38_genome_config{local_files} })
{
  my $local_file = File::Spec->catfile( $local_dir, $chr_file );
  my $fh = new IO::Uncompress::Gunzip $local_file ||
    die "gzip failed: $GunzipError\n";

  ( my $chr = $chr_file ) =~ s/\.fa\.gz//;
  $chr_lens{ $chr } = length $test_genome_seq;
  while (<$fh>)
  {
    chomp $_;
    next if $_ =~ m/\A>/;
    $test_genome_seq .= $1 if ( $_ =~ m/(\A[ATCGNatcgn]+)\Z/);
  }
  $chr_lens{genome} = length $test_genome_seq;
}
$hg38_genome_config{'length'} = $chr_lens{genome};
$hg38_genome_config{chr_len} = \%chr_lens;

# check obj creation
my $hg38_gst = $package->new( \%hg38_genome_config );
ok ( ( $hg38_gst
      && (blessed $hg38_gst || !ref $hg38_gst)
      && $hg38_gst->isa($package) )
    , "$package obj created");


# test charGenome stuff for 'score' type
{
  my @test_scores;
  for (my $i = -60; $i < 61; $i++)
  {
    push @test_scores, $i / 2;
  }
  my $track_name = 'test';
  my (@obs_scores, @exp_scores);
  my $score2char_phyloP = sub { my ( $score ) = @_;
                                int( $score * ( 127 / 30 ) ) + 128
                              };
  my $char2score_phyloP = sub { my ( $char ) = @_;
      ( $char && $char > 0 )
      ? sprintf("%0.3f", eval(($_[0] - 128) / (127 / 30)))
      : undef
  };
  my $char_genome_track = $package->new( {
        name => $track_name,
        length => $#test_scores,
        char2score => $char2score_phyloP,
        score2char => $score2char_phyloP,
        chr_len => { },
        genome_chrs => [ ],
        type => 'score',
      }
  );
  isa_ok($char_genome_track, $package, "$package obj created with phyloP constructors");
  is($char_genome_track->name, $track_name, "$package name set correctly");


  # check the build script initialized zeros for the specified length
  for my $i (0..$#test_scores)
  {
    push @obs_scores, $char_genome_track->get_score($i);
    push @exp_scores, undef;
  }
  is_deeply(\@obs_scores, \@exp_scores,
    "sequence initalized with length, $#test_scores");

  # insert test scores into seq and check values were inserted correctly
TODO: {
    local $TODO = 'retreive scores';
    for my $i (0..$#test_scores)
    {
      $char_genome_track->insert_score($i, $test_scores[$i]);
    }
    (@obs_scores, @exp_scores) = ( );
    for my $i (0..$#test_scores)
    {
      push @obs_scores, $char_genome_track->get_score($i);
      push @exp_scores, sprintf("%0.3f", $test_scores[$i]);
    }
    is_deeply(\@obs_scores, \@exp_scores, 'scores retrieved from seq');
  }
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
