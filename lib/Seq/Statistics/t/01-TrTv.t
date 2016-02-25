use 5.10.0;
use strict;
use warnings;

package MockStatistics;
use Moose;
use Seq::Statistics;

my $pinf = 1e9999;  

has statisticsCalculator => (
  is      => 'ro',
  isa     => 'Seq::Statistics',
  handles => {
    recordStat     => 'record',
    summarizeStats => 'summarize',
    statsRecord    => 'statsRecord',
    storeStats     => 'storeStats',
  },
  lazy     => 1,
  required => 1,
  builder  => '_buildStatistics',
);

sub _buildStatistics {
  my $self = shift;
  return Seq::Statistics->new( debug => 0 );
}

sub annotate {
  my $self = shift;
  my $id_genos_href = shift;

  my $record_href = {ref_base => 'G', var_type => 'MULTIALLELIC', genomic_type => 'Exonic'};
  my $gene_data_aref = [1,2]; #just needs to be longer than 1 to stop workign after tr:tv count
  my $snp_data_aref = [];

  return $self->recordStat( $id_genos_href, [ $record_href->{var_type}, $record_href->{genomic_type} ],
    $record_href->{ref_base}, $gene_data_aref, $snp_data_aref );
}

sub _getMixed {
  return {
    "P1" => "S",
    "P2" =>  "S",
    "P3" =>  "C",
    "P4" => "G",
    "P5" => "A"
  }
}

sub getTransversions {
  return {
    "P1" => "S",
    "P2" =>  "S",
    "P3" =>  "S",
    "P4" => "S",
    "P5" => "S"
  }
}

sub getTransitions {
  return {
    "P1" => "A",
    "P2" =>  "A",
    "P3" =>  "A",
    "P4" => "A",
    "P5" => "A"
  }
}

sub threeTransversionsTwoN {
  return {
    "P1" => "S",
    "P2" =>  "S",
    "P3" =>  "S",
    "P4" => "N",
    "P5" => "N",
  }
}

sub threeTransitionsTwoN {
  return {
    "P1" => "A",
    "P2" =>  "A",
    "P3" =>  "A",
    "P4" => "N",
    "P5" => "N",
  }
}

sub oneTransition {
  return {
    "P1" => "A",
  }
}

sub twoTransversions {
  return {
    "P2" => "S",
    "P3" => "S",
  }
}

sub allWeirdBases {
  return {
    "P1" => "Q",
    "P2" =>  "-9",
    "P3" =>  "D",
    "P4" => "WS",
    "P5" => "I",
  }
}


package UseStatistics;
use Test::More qw(no_plan);
use DDP;

my $annotator = MockStatistics->new();

$annotator->annotate($annotator->getTransitions);
$annotator->annotate($annotator->getTransversions);
$annotator->annotate($annotator->threeTransitionsTwoN);

#P1: 2:1
#P2: 2:1 ratio
#P3: 2:1 ratio
#P4: 1:1 ratio
#P5: 1:1 ratio;
$annotator->summarizeStats();

my $stats = $annotator->statsRecord();

my $median = $stats->{statistics}{percentiles}{'Transitions:Transversions'}{median};
my $bottom = $stats->{statistics}{percentiles}{'Transitions:Transversions'}{'5th'};
my $top = $stats->{statistics}{percentiles}{'Transitions:Transversions'}{'95th'};

my $p5sampleTrTv = $stats->{P5}{statistics}{'Transitions:Transversions'};

p $stats;
ok($stats->{P1}{statistics}{'Transitions:Transversions'} == 2, 
  'sample has ok Tr:Tv when normal base calls supplied');
ok($stats->{P5}{statistics}{'Transitions:Transversions'} == 1
  , 'sample has ok Tr:Tv when bases called include those that aren\'t Transition or Transversion');
ok($median == 2, 'median stat ok');
ok($bottom == 1, '5th percentile stat ok');
ok($top == 2, '95th percentile stat ok');

$annotator = MockStatistics->new();

$annotator->annotate($annotator->getTransversions);

$annotator->summarizeStats();

$stats = $annotator->statsRecord();

$median = $stats->{statistics}{percentiles}{'Transitions:Transversions'}{median};
$bottom = $stats->{statistics}{percentiles}{'Transitions:Transversions'}{'5th'};
$top = $stats->{statistics}{percentiles}{'Transitions:Transversions'}{'95th'};

ok($stats->{P1}{statistics}{'Transitions:Transversions'} == 0, 'sample ratio ok when no Transitions called');
ok($median == 0, 'median stat ok when no Transitions');
ok($bottom == 0, '5th percentile stat ok when no Transitions');
ok($top == 0, '95th percentile stat ok when no Transitions');

p $stats;

$annotator = MockStatistics->new();

$annotator->annotate($annotator->allWeirdBases() );

$annotator->summarizeStats();

$stats = $annotator->statsRecord();

ok(!defined $stats->{P1}{Transitions}, 'weird bases don\'t generate stats' );
ok(!defined $stats->{statistics}{percentiles}, 'weird bases don\'t generate percentile stats' );


$annotator = MockStatistics->new();

$annotator->annotate($annotator->getTransitions() );

$annotator->summarizeStats();

$stats = $annotator->statsRecord();

$median = $stats->{statistics}{percentiles}{"Transitions:Transversions"}{median};
$bottom = $stats->{statistics}{percentiles}{"Transitions:Transversions"}{"5th"};
$top = $stats->{statistics}{percentiles}{"Transitions:Transversions"}{"95th"};

ok($stats->{P1}{statistics}{'Transitions:Transversions'} == $pinf,
  "sample Tr:Tv ok when only statistics called (giving $pinf ratio)");
ok($median == $pinf, "median ok when only Transitions called (infinite: $pinf)");
ok($bottom == $pinf, "5th percentile ok when only Transitions called");
ok($top == $pinf, "95th percentile ok when only Transitions called");
p $stats;


$annotator = MockStatistics->new();

$annotator->annotate($annotator->threeTransversionsTwoN);

$annotator->summarizeStats();

$stats = $annotator->statsRecord();

$median = $stats->{statistics}{percentiles}{"Transitions:Transversions"}{median};
$bottom = $stats->{statistics}{percentiles}{"Transitions:Transversions"}{"5th"};;
$top = $stats->{statistics}{percentiles}{"Transitions:Transversions"}{"95th"};

p $stats;
ok(!defined $stats->{P5}{statistics}{"Transitions:Transversions"}, "N gives undefined ratio");
ok($median == 0, "with some undefined ratios, median ok");
ok($bottom == 0, "with some undefined ratios, 5th percentile ok");
ok($top == 0, "with some undefined ratios, 95th percentile ok");

$annotator = MockStatistics->new();

$annotator->annotate($annotator->threeTransitionsTwoN);
$annotator->annotate($annotator->threeTransversionsTwoN);

$annotator->summarizeStats();

$stats = $annotator->statsRecord();

$median = $stats->{statistics}{percentiles}{"Transitions:Transversions"}{median};
$bottom = $stats->{statistics}{percentiles}{"Transitions:Transversions"}{"5th"};;
$top = $stats->{statistics}{percentiles}{"Transitions:Transversions"}{"95th"};

p $stats;
ok(!defined $stats->{P5}{statistics}{"Transitions:Transversions"}, "N gives undefined ratio");
ok($median == 1, "with some undefined ratios, median ok");
ok($bottom == 1, "with some undefined ratios, 5th percentile ok");
ok($top == 1, "with some undefined ratios, 95th percentile ok");


$annotator = MockStatistics->new();

$annotator->annotate($annotator->oneTransition);
$annotator->annotate($annotator->threeTransversionsTwoN);

#P1: TR:TV = 1/1
#P2: TR:TV = 0/1
#P3: TR:TV = 0/1
#P4: TR:TV = undef
#P4: TR:TV = undef

#for 95th
#we may expect interpolation between 0 and 1 for 95th, such that
#we interpolate between indexes rather than ranks, we could also interpolate between ranks 

#so we may expect if using rank interpolation:
# 3 (total number of ratios) * .95 = 2.85
# distance from floor (2.85 - 2) = .85
# value at ceiling index (rank 3, index 2) * distance from floor: (1*.85)
# value at floor index (rank 2, index 1) * distance from ceil: (0*.25)

#and for index interpolation:
# 2 (last sorted index) * .95 = 1.9
# distance from floor (1.9 - 1) = .9
# value at ceiling index (rank 3, index 2) * distance from floor: (1*.9) = .9
# value at floor index (rank 2, index 1) * distance from ceil: (0*.1) = 0

$annotator->summarizeStats();

$stats = $annotator->statsRecord();

$median = $stats->{statistics}{percentiles}{"Transitions:Transversions"}{median};
$bottom = $stats->{statistics}{percentiles}{"Transitions:Transversions"}{"5th"};;
$top = $stats->{statistics}{percentiles}{"Transitions:Transversions"}{"95th"};

p $stats;
ok($stats->{P1}{statistics}{"Transitions:Transversions"} == 1, 'sample ratio ok');
ok($stats->{P2}{statistics}{"Transitions:Transversions"} == 0, 'sample ratio ok');
ok(!defined $stats->{P5}{statistics}{"Transitions:Transversions"}, "N gives undefined ratio");
ok($median == 0, "median ok in interpoloation");
ok($bottom == 0, "5th percentile ok when using index interpolation");

#because floating point comparisons can fail when their underlying bit representations
#are not identical, which is a bit weird to me.
ok($top eq 0.9, "95th percentile ok when using index interpolation");
