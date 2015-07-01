#!/usr/bin/env perl
# Name:           snpfile_annotate_mongo_redis_queue.pl
# Description:
# Date Created:   Wed Dec 24
# By:             Alex Kotlar
# Requires: Snpfile::AnnotatorBase

# TODO: Handle job expiration (what happens when job:id expired; make sure no other job operations happen, let Node know via sess:?)
# There may be much more performant ways of handling this without loss of reliability; loook at just storing entire message in perl, and relying on decode_json
# TODO: (Probably in Node.js): add failed jobs, and those stuck in processingJobs list for too long, back into job queue, for N attempts (stored in jobs:jobID)

use 5.20.1;
use autodie;
use Cpanel::JSON::XS;

use strict;
use warnings;

use Try::Tiny;

use lib '../lib';
use threads;
use threads::shared;

use Log::Any::Adapter;
use File::Basename;
use Seq;

use Thread::Queue;
use IO::Socket;
use Sys::Info;
use Sys::Info::Constants qw( :device_cpu )
  ; #for choosing max connections based on available resources

use Data::Dumper;

use Redis;

my $DEV                = 1;
my $redisHost : shared = 'localhost';
my $redisPort : shared = '6379';

my $jobQueueName : shared          = 'submittedJobsQueue';
my $jobsProcessingQueue : shared   = 'processingJobsQueue';
my $jobsFinishedQueueName : shared = 'finishedJobsQueue';
my $jobsFailedQueueName : shared   = 'failedJobsQueue';
my $jobsFinalFailedListName : shared = 'failedJobsList'; #those that won't be retried
my $submittedJobsDocument : shared   = 'submittedJobs';
my $annotationMessageChannel : shared = 'annotationProgress';

my $configPathBaseDir : shared = "../config/";
my $configFilePathHref : shared = shared_clone( {} );

my $maxAttempts : shared = 4;

my $semSTDOUT : shared;

sub tprint  { lock $semSTDOUT; print @_; }
sub treturn { lock $semSTDOUT; return @_; }

$|++;

my %cache;

my $Qwork : shared = new Thread::Queue;

my $Qdone : shared = new Thread::Queue;

my $done : shared = 0;

my $info = Sys::Info->new;

my $cpu = $info->device( CPU => my %options );

my $verbose : shared = 1;

#handle success and failure
#expects $redis from local scope (not passed)
#look into multi-exec consequences, performance, investigate storing in redis Sets instead of linked-lists
sub handleJobSuccess {
  my ( $jobID, $jobKey, $returnJSONreference, $redis ) = @_;

  try {
    my $jsonAnnotationSummary = { 'annotationSummary' =>
        encode_json( $returnJSONreference->{'annotationSummary'} ) };

    if ( !$jsonAnnotationSummary->{'annotationSummary'} ) {
      die "No annotation summary generated in handleJobs line 80!";
    }

    #use multi/exec transactions;
    $redis->multi;
    $redis->hset( $jobKey, %$jsonAnnotationSummary );
    $redis->rpush( $jobsFinishedQueueName, $jobID );
    $redis->lrem( $jobsFailedQueueName, 0, $jobID );
    $redis->lrem( $jobsProcessingQueue, 0, $jobID );
    $redis->exec;
  }
  catch {
    print "Error in handleJobSuccess: $_";

    handleJobFailure( $jobID, $jobKey, $redis );
  }
}

#todo, find better error handling, seems not to work when using try catch
sub handleJobFailure {
  my ( $jobID, $jobKey, $redis ) = @_;

  print Dumper($jobKey);
  try {
    my $jobAttempts =
      $redis->hincrby( $jobKey, 'attempts', 1 ); #returns int of attempts after increment

    $redis->multi;
    $redis->lrem( $jobsFailedQueueName, 0, $jobID );

    if ( $jobAttempts > $maxAttempts ) {
      $redis->lpush( $jobsFinalFailedListName, $jobID );
    }
    else {
      $redis->lpush( $jobsFailedQueueName, $jobID );
    }

    $redis->lrem( $jobsProcessingQueue, 0, $jobID );
    $redis->exec;
  }
  catch {
    print $_;
  }
}

sub handleJob {
  my $jobID = shift;

  #also has maxAttempts

  my %user_uploads_dirs = ();
  my $annotationJson;
  my ( $inputFile, $outputDir, @submittedJobArray, $jobDetailsHref,
    $returnJSONreference, $jobAttemptsCount, $userID );

  my $jobKey = $submittedJobsDocument . ':' . $jobID;

  my $redis = Redis->new( host => $redisHost, port => $redisPort );

  my $log;
  try {
    @submittedJobArray = $redis->hmget( $jobKey, 'attempts', 'jobDetails' );

    $jobAttemptsCount = $submittedJobArray[0];

    if ( $jobAttemptsCount > $maxAttempts ) {
      die "No more attempts remaining";
    }

    $jobDetailsHref = decode_json( $submittedJobArray[1] );

    my $inputHref = coerceInputs($jobDetailsHref);

    # set log file
    my $log_name = join '.', 'annotation', 'jobID',
      $inputHref->{messageChannelHref}->{recordLocator}->{jobID}
      , #jobID should be the most atomic, no need to expose userID
      'log';

    my $log_file = File::Spec->rel2abs( ".", $log_name );
    say "writing log file here: $log_file" if $verbose;
    Log::Any::Adapter->set( 'File', $log_file );

    $log = Log::Any->get_logger();

    $redis->publish(
      $inputHref->{messageChannelHref}->{messageChannel},
      encode_json(
        {
          %{ $inputHref->{messageChannelHref}->{recordLocator} },
          message => 'Pushing job to SeqAnt annotator'
        }
      )
    );

    # sanity checks mostly now not needed, will be checked in Seq.pm using MooseX:Type:Path:Tiny
    # if ( -f $out_file && !$force )
    # {
    #   say "ERROR: '$out_file' already exists. Use '--force' switch to over write it.";
    #   exit;
    # }

    # get absolute path not needed anymore, handled by coercison in Seq.pm, closer to where file is actually written

    # create the annotator
    my $annotate_instance = Seq->new($inputHref);

    # annotate the snp file
    my $annotationJson = encode_json( $annotate_instance->annotate_snpfile );

    if ( !$annotationJson ) {
      die "No json returned from annotator";
    }
  }
  catch {
    say $_;

    $log->error($_);

    handleJobFailure( $jobID, $jobKey, $redis );
  };

  if ($annotationJson) {
    try {
      $returnJSONreference = decode_json($annotationJson);

      return 1;
    }
    catch {
      say "Error in decoding returned JSON $_";

      $log->error($_);

      handleJobFailure( $jobID, $jobKey, $redis );
    };

    handleJobSuccess( $jobID, $jobKey, $returnJSONreference, $redis );
  }
}

# how many threads we allow in the pool
# what does //= do here?
#!($cpu->count % 2) ? $cpu->count / 2 : !($cpu->count % 3) ? $cpu->count / 3 : $cpu->count || 1;
our $W //=
    !( $cpu->count % 2 ) ? $cpu->count / 2
  : !( $cpu->count % 3 ) ? $cpu->count / 3
  :                        $cpu->count || 1;

my @workers = map threads->create( \&worker, \%cache ), 1 .. $W;

sub worker {
  my $tid = threads->tid;

  #dequeue takes the socket connection from the head of the $Qwork array

  ###Todo consider performance implications, benefits of storing just key in list, using hmget to modify the job itself.
  ## Noted danger: if decode_json doesn't work properly, mangled messgae; this is an advantage of using hmget & hmset

  #expects from global scope $redis (redis client)
  while ( my $jobID = $Qwork->dequeue ) #do something on $data
  {
    handleJob($jobID);

    $Qdone->enqueue($jobID);
  }
}

#Here we may wish to read a json or yaml file containing argument mappings
sub coerceInputs {
  my $jobDetailsHref = shift;
  print Dumper($jobDetailsHref);

  my $filePath = findFilePath($jobDetailsHref);

  my $debug = !!$DEV; #not, not!

  my $configFilePath = $jobDetailsHref->{configFilePath}
    || getConfigFilePath( $jobDetailsHref->{assembly} );

  my $userID = $jobDetailsHref->{'userID'} || $jobDetailsHref->{'sessionID'};

  my $redisChannelDetailsHref = {
    'messageChannel' => $annotationMessageChannel,
    'recordLocator'  => {
      'jobID'  => $jobDetailsHref->{jobID},
      'userID' => $userID
    }
  };

  print Dumper($redisChannelDetailsHref);

  return {
    snpfile            => $filePath,
    out_file           => $jobDetailsHref->{'outDir'},
    configfile         => $configFilePath,
    debug              => $debug,
    messageChannelHref => $redisChannelDetailsHref
    }

    # snpfile    => $jobDetailsHref->{'file'},
    #       configfile => $yaml_config,
    #       out_file   => $out_file,
    #       debug      => $debug,
    #       redisChannelDetailsHref => $redisChannelDetailsHref
}

sub findFilePath {
  my $jobDetailsHref = shift;

  while ( my ( $key, $value ) = each %{ $jobDetailsHref->{'uploadedFiles'} } ) {
    if ( $key =~ m/.*file/gi ) {
      return $value; #only support one file for now
    }
  }
}

sub getConfigFilePath {
  my $assembly = shift;

  if ( exists $configFilePathHref->{$assembly} ) {
    return $configFilePathHref->{$assembly};
  }
  else {
    my @maybePath = glob( $configPathBaseDir . $assembly . ".y*ml" );
    if ( scalar @maybePath ) {
      if ( scalar @maybePath > 1 ) {
        #should log
        say "\n\nMore than 1 config path found, choosing first";
      }

      return $maybePath[0];
    }

    die "\n\nNo config path found for the assembly $assembly. Exiting\n\n"
      ; #throws the error
    #should log here
  }
}

my @listenerThreads;

my $normalQueue = threads->new(
  sub {
    my $redis = Redis->new( host => $redisHost, port => $redisPort );

    while (1) {
      my $jobID : shared = $redis->brpoplpush( $jobQueueName, $jobsProcessingQueue, 0 )
        ; #this can result in N identical items in $jobsProcessingQueue; resolved on completion of job on lines 89,116

      if ($jobID) {
        print "\n\nGOT $jobID";

        $cache{$jobID} = $jobID;

        $Qwork->enqueue($jobID);
      }

      delete $cache{ $Qdone->dequeue } while $Qdone->pending;
    }
  }
);

push @listenerThreads, $normalQueue;

my $failedQueue = threads->new(
  sub {
    my $redis = Redis->new( host => $redisHost, port => $redisPort );

    while (1) {
      my $jobID : shared =
        $redis->brpoplpush( $jobsFailedQueueName, $jobsProcessingQueue, 0 )
        ; #this can result in N identical items in $jobsProcessingQueue; resolved on completion of job on lines 89,116

      if ($jobID) {
        print "\n\nGOT $jobID on line 276";

        $cache{$jobID} = $jobID;

        $Qwork->enqueue($jobID);
      }

      delete $cache{ $Qdone->dequeue } while $Qdone->pending;
    }
  }
);

push @listenerThreads, $failedQueue;

#If user presses control+C exit
$SIG{INT} = sub {
  print "Got control + c";
  #close the listener
  $done = 1;

  #set all
  $Qwork->enqueue( (undef) x $W );

  $_->kill('KILL')->kill() for @listenerThreads; #not working
};

$_->join for @workers;

#$_->join for @listenerThreads;

tprint "Listener closed";

tprint "Workers done";

__END__
=head1 NAME

socket_snpfile_annotate_mongo.pl

=head1 SYNOPSIS

Add synopsis

=head1 DESCRIPTION

This programs runs a persistent socket server, listens for entries, runs requested annotation

etc
=cut
