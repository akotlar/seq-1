use 5.10.0;
use strict;
use warnings;

use lib './lib';
use Carp;
use Getopt::Long;
use File::Spec;

use Pod::Usage;
use Type::Params qw/ compile /;
use Types::Standard qw/ :type /;
use Log::Any::Adapter;
use YAML::XS qw/ LoadFile /;

use threads;
use threads::shared;
use Thread::Queue;
use IO::Socket;
use Cpanel::JSON::XS;
use Data::Dumper;

use Try::Tiny;

use Benchmark qw(:all);

use Seq;

my $semSTDOUT : shared;

sub tprint  { lock $semSTDOUT; print @_; }
sub treturn { lock $semSTDOUT; return @_; }

$|++;

my %cache;

my $Qwork = new Thread::Queue;

my $Qdone = new Thread::Queue;

my $done : shared = 0;

#
sub worker {
  my $tid = threads->tid;

  #dequeue takes the socket connection from the head of the $Qwork array
  while ( my $fno = $Qwork->dequeue ) {
    open my $client, "+<&", $fno or die $!;
    tprint "$tid: Duped $fno to $client";
    my $buffer     = '';
    my $JSONObject = Cpanel::JSON::XS->new->ascii->pretty->allow_nonref();
    my %user_choices;

    while ( my $c = sysread( $client, $buffer, 1, length $buffer ) ) {
      last if $done;
    }

    if ( $buffer !~ m/^end/gi && $buffer !~ m/^\z/gi ) {
      %user_choices = %{ $JSONObject->decode($buffer) };

      print Dumper( \%user_choices );
      my $out_file    = $user_choices{o}        || $user_choices{outfile} | "";
      my $force       = $user_choices{f}        || $user_choices{force};
      my $db_location = $user_choices{location} || $user_choices{l} | "";
      my $snpfile     = $user_choices{s}        || $user_choices{snpfile} || "";
      my $yaml_config = $user_choices{c}        || $user_choices{config} || "";
      my $verbose     = $user_choices{v}        || $user_choices{verbose};
      my $debug       = $user_choices{d}        || $user_choices{debug};

      # sanity checks mostly now not needed, will be checked in Seq.pm using MooseX:Type:Path:Tiny
      if ( -f $out_file && !$force ) {
        say "ERROR: '$out_file' already exists. Use '--force' switch to over write it.";
        exit;
      }

      # get absolute path not needed anymore, handled by coercison in Seq.pm, closer to where file is actually written

      # read config file to determine genome name for loging and to check validity of config
      # read config file to determine genome name for loging and to check validity of config
      my $config_href = LoadFile($yaml_config)
        || die "ERROR: Cannot read YAML file - $yaml_config: $!\n";

      # set log file
      my $log_name = join '.', 'annotation', $config_href->{genome_name}, 'log';
      my $log_file = File::Spec->rel2abs( ".", $log_name );
      say "writing log file here: $log_file" if $verbose;
      Log::Any::Adapter->set( 'File', $log_file );

      try {
        # create the annotator
        my $annotate_instance = Seq->new(
          {
            snpfile    => $snpfile,
            configfile => $yaml_config,
            out_file   => $out_file,
            debug      => $debug,
          }
        );
        cmpthese(
          50,
          {
            a => sub {

              # annotate the snp file
              $annotate_instance->annotate_snpfile;
            }
          }
        );
      }
      catch {
        #print "caught error: $_"; # not $@
        } finally {
        if (@_) {
          print "The try block died with: @_\n";
        }
        };

      print "Done!";

      close $client;

      $Qdone->enqueue($fno);
    }
  }
}

# how many threads we allow in the pool
our $W = 8;

my $lsn = new IO::Socket::INET(
  Listen    => 5,
  LocalPort => '9003',
  Reuse     => 1
) or die "Failed to open listening port: $!\n";

my @workers = map threads->create( \&worker, \%cache ), 1 .. $W;

while ( my $client = $lsn->accept ) {
  my $fno = fileno $client;

  $cache{$fno} = $client;

  $Qwork->enqueue($fno);

  delete $cache{ $Qdone->dequeue } while $Qdone->pending;
}

#If user presses control+C exit
$SIG{INT} = sub {
  #close the listener
  close $lsn;

  $done = 1;

  #set all
  $Qwork->enqueue( (undef) x $W );
};

tprint "Listener closed";

$_->join for @workers;

tprint "Workers done";
