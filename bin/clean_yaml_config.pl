#!/usr/bin/env perl
use Modern::Perl qw(2013);
use YAML::XS qw(Dump Load LoadFile);
use Getopt::Long;
use Pod::Usage;
use Time::localtime;
use Scalar::Util qw( reftype );
use DDP;

# variables
my ( $config_file, $help, $print_clean_file, $untaint );
my $now_timestamp = sprintf( "%d-%02d-%02d",
  ( localtime->year() + 1900 ),
  ( localtime->mon() + 1 ),
  localtime->mday() );

# process command line arguments
GetOptions(
  'f|file=s'  => \$config_file,
  'p|print'   => \$print_clean_file,
  'u|untaint' => \$untaint,
  'h|help'    => \$help
);
pod2usage(1) if $help;
pod2usage(2) unless $config_file;

if ($untaint) {
  open my $in_fh, '<', $config_file;
  my $cleaned_txt;
  while (<$in_fh>) {
    chomp $_;
    if ( $_ =~ /\A#/ ) {
      say "ignoring comment in $config_file: $_";
    }
    elsif ( $_ =~ m/\A([\-\=\:\/\t\s\w.]+)\Z/ ) {
      $cleaned_txt .= $1 . "\n";
    }
    elsif ( $_ =~ m/\A\s*\Z/ ) {
      say "skipping blank line in $config_file: $_";
    }
    else {
      die "Bad data in $config_file: $_\n";
    }
  }
  say $cleaned_txt;
  my $opt_href = Load($cleaned_txt);
  print Dump $opt_href;
  p $opt_href;
}
else {
  # load the yaml file
  my $config_href = LoadFile($config_file)
    || die "cannot load $config_file: $!\n";
  p $config_href;

  for my $i ( keys %$config_href ) {
    my $type //= reftype $config_href->{$i};
    if ($type) {
      if ( $type eq "ARRAY" ) {
        say join( " ", $i, scalar @{ $config_href->{$i} } );
        print Dump( $config_href->{$i} );
      }
    }
    else {
      say $i;
    }
  }

  # print cleaned yaml configuration file if there were no errors
  unless ($print_clean_file) {
    my $out_file = "clean.$now_timestamp." . $config_file;
    open my $out_fh, ">", $out_file;
    print $out_fh Dump($config_href);
    close $out_fh;
  }
}
__END__

=head1 NAME

clean_yaml_config.pl

=head1 SYNOPSIS

clean_yaml_config.pl [-h|help] -f|file <yaml_configuration_file>

=head1 OPTIONS

=over 8

=item -f|file

Annotation configuration file in YAML format for `init_annotation_data.pl`

=item -h|help

Prints help information.
