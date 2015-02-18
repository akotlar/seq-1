#!perl -T
use 5.10.0;
use strict;
use warnings;
use Test::More;
use Scalar::Util qw( blessed );

plan tests => 22;

BEGIN
{
  chdir("./t");
}
 

# test the package's attributes and type constraints
my $package = "Seq::Build::GenomeSizedTrack";

# load package
use_ok($package) || die "$package cannot be loaded";

# check package uses Moose
ok( $package->can('meta'), "$package has a meta() method" )
  or BAIL_OUT("$package does not have a meta() method.");

# check type constraints for attributes that should have Str values
for my $attr_name (qw( name ))
{
  my $attr = $package->meta->get_attribute($attr_name);
  ok( $attr->has_type_constraint, "$package $attr_name has a type constraint");
  is( $attr->type_constraint->name, 'Str', "$attr_name type is Str" );
}

# check type constraints for attributes that should have Int values
for my $attr_name (qw( length ))
{
  my $attr = $package->meta->get_attribute($attr_name);
  ok( $attr->has_type_constraint, "$package $attr_name has a type constraint");
  is( $attr->type_constraint->name, 'Int', "$attr_name type is Int" );
}

# check type constraints for attributes that should have Int values
for my $attr_name (qw( char_seq str_seq ))
{
  my $attr = $package->meta->get_attribute($attr_name);
  ok( $attr->has_type_constraint, "$package $attr_name has a type constraint");
  is( $attr->type_constraint->name, 'ScalarRef[Str]',
    "$attr_name type is ScalarRef[Str]" );
}

# check type constraints for attributes that should have Int values
for my $attr_name (qw( char2score score2char ))
{
  my $attr = $package->meta->get_attribute($attr_name);
  ok( $attr->has_type_constraint, "$package $attr_name has a type constraint");
  is( $attr->type_constraint->name, 'CodeRef', "$attr_name type is CodeRef" );
}

# check obj creation
my $generic_genome_track = Seq::Build::GenomeSizedTrack->new( { name => 'test' } );
ok ( ( $generic_genome_track 
      && (blessed $generic_genome_track || !ref $generic_genome_track)
      && $generic_genome_track->isa($package) )
    , "$package obj created");


# test charGenome stuff
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
  my $char_genome_track = Seq::Build::GenomeSizedTrack->new( {
        name => $track_name,
        length => $#test_scores,
        char2score => $char2score_phyloP,
        score2char => $score2char_phyloP,
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

# make a genome string with single bases
{
  my $track_name = 'Test';
  my $str_genome_track = Seq::Build::GenomeSizedTrack->new( {
        name => $track_name,
      }
  );
  my @test_bases = qw( A C T G );
  my $test_str   = join("", @test_bases);
  for my $base (@test_bases)
  {
    $str_genome_track->push_str($base);
  }
  is($str_genome_track->say_str, $test_str, 'build str seq from bases');
}

# make a genome string with large strings of bases
{
  my $track_name = 'Test';
  my $str_genome_track = Seq::Build::GenomeSizedTrack->new( {
        name => $track_name,
      }
  );

  my @test_base_rows = qw( AAAAAAA CCCCCC TTTTTT GGGGGGG );
  my $test_str       = join("", @test_base_rows);
  for my $base_row (@test_base_rows)
  {
    $str_genome_track->push_str($base_row);
  }
  is($str_genome_track->say_str, $test_str, 'build str seq from rows of bases');
}

# get a string of DNA bases from an arbitrary locaiton
{
  my $track_name = 'test';
  my $str_genome_track = Seq::Build::GenomeSizedTrack->new( {
      name => $track_name,
    }
  );
  my @test_bases = qw( A C T G C A G T );
  my (@obs_bases, @exp_bases);
  for my $base (@test_bases)
  {
    $str_genome_track->push_str($base);
  }

  for (my $i=$#test_bases; $i >= 0; $i--)
  {
    push @exp_bases, $test_bases[$i];
    push @obs_bases, $str_genome_track->get_str( $i );
  }
  is_deeply(\@obs_bases, \@exp_bases, 'substring out correct base');
}
