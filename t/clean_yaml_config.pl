#!/usr/bin/env perl
use Modern::Perl qw(2013);
use YAML::XS qw(Dump LoadFile);
use Getopt::Long;
use Pod::Usage;
use Time::localtime;
use Scalar::Util qw( reftype );

# variables
my ( $config_file, $help, $print_clean_file );
my $now_timestamp = sprintf( "%d-%02d-%02d",
                             eval( localtime->year() + 1900 ),
                             eval( localtime->mon() + 1 ),
                             localtime->mday() );

# process command line arguments
GetOptions( 'f|file=s' => \$config_file,
            'p|print'  => \$print_clean_file,
            'h|help'   => \$help );
pod2usage(1) if $help;
pod2usage(2) unless $config_file;

# load the yaml file
my $config_href = LoadFile($config_file) || die "cannot load $config_file: $!\n";

say "=" x 80;
print Dump($config_href);
say "=" x 80;

for my $i (keys %$config_href)
{
  my $type //= reftype $config_href->{$i};
  if ($type)
  {
    if ($type eq "ARRAY")
    {
      say join(" ", $i, scalar @{ $config_href->{$i}});
      print Dump($config_href->{$i});
    }
  }
  else
  {
    say $i;
  }
}


# print cleaned yaml configuration file if there were no errors
unless ($print_clean_file)
{
    my $out_file = "clean.$now_timestamp." . $config_file;
    open my $out_fh, ">", $out_file;
    print $out_fh Dump($config_href);
    close $out_fh;
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
