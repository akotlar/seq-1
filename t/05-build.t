#!perl -T
use 5.10.0;
use strict;
use warnings;
use Test::More;
use File::Copy;
use File::Path qw/ make_path /;
use Scalar::Util qw/ blessed /;
use Lingua::EN::Inflect qw/ A PL_N /;
use Log::Any::Adapter;
use Path::Tiny;
use DDP;

if ( $ENV{PERL_MONGODB_DEBUG} ) {
  Log::Any::Adapter->set('Stdout');
}

plan tests => 4;

# set test genome
my $hg38_node03_config = path('./config/hg38_node03.yml')->absolute->stringify;
my $hg38_local_config  = path('./config/hg38_local.yml')->absolute->stringify;

# setup testing enviroment
{
  make_path('./sandbox') unless -d './sandbox';
  chdir("./sandbox");
}

use_ok('Seq::Build') || print "Bail out!\n";

my $build_hg38 =
  Seq::Build->new_with_config( { configfile => $hg38_node03_config } );
isa_ok( $build_hg38, 'Seq::Build', 'built Seq::Build with config file' );
is( 'mongodb://192.168.15.103', $build_hg38->mongo_addr, 'remote mongodb address' );
$build_hg38 = Seq::Build->new_with_config( { configfile => $hg38_local_config } );
is( 'mongodb://127.0.0.1', $build_hg38->mongo_addr, 'local mongodb address' );

__END__
