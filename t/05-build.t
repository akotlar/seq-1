#!perl -T
use 5.10.0;
use strict;
use warnings;
use Test::More;
use File::Copy;
use Scalar::Util qw( blessed );
use DDP;
use Lingua::EN::Inflect qw( A PL_N );
use Log::Any::Adapter;

if ( $ENV{PERL_MONGODB_DEBUG} ) {
    Log::Any::Adapter->set('Stdout');
}

plan tests => 2;

# set test genome
my $hg38_config_file = 'hg38_build_test.yml';

# setup testing enviroment
{
  copy ("./t/$hg38_config_file", "./sandbox/$hg38_config_file")
    or die "cannot copy ./t/$hg38_config_file to ./sandbox/$hg38_config_file $!";
  chdir("./sandbox");
}

use_ok( 'Seq::Build' ) || print "Bail out!\n";

my $build_hg38 = Seq::Build->new_with_config( configfile => $hg38_config_file );
isa_ok( $build_hg38, 'Seq::Build', 'built Seq::Build with config file' );

$build_hg38->build_index;


__END__
