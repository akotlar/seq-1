package Seq::ConfigFromFile;

use 5.10.0;
use autodie;
use Carp qw( croak );
use Moose::Role;
use MooseX::Types::Path::Tiny 0.005 'Path';
use MooseX::Types::Moose 'Undef';
use namespace::autoclean;
use YAML::XS qw( Load );

has configfile => (
    is => 'ro',
    isa => Path|Undef,
    coerce => 1,
    predicate => 'has_configfile',
    eval "require MooseX::Getopt; 1" ? (traits => ['Getopt']) : (),
    lazy => 1,
    # it sucks that we have to do this rather than using a builder, but some old code
    # simply swaps in a new default sub into the attr definition
    default => sub {
        my $class = shift;
        $class->_get_default_configfile if $class->can('_get_default_configfile');
    },
);


=head1 NAME

Seq::Config - The great new Seq::Config!

=head1 VERSION

Version 0.01

=cut

our $VERSION = '0.01';

=head1 SYNOPSIS

Set, get, and check configuration.

Most of the code is taken from `MooseX::ConfigFromFile`. It would have been too
much of a pain to do it the way they envisoned since we build off a hashref and
not a hash, which is what that module returns. Easier to modify the module's
behavior. Comments and code from the module are left-as-is.

=cut

sub new_with_config {
    my ($class, %opts) = @_;

    my $configfile;

    if(defined $opts{configfile}) {
        $configfile = $opts{configfile}
    }
    else {
        # This would only succeed if the consumer had defined a new configfile
        # sub to override the generated reader - as suggested in old
        # documentation -- or if $class is an instance not a class name
        $configfile = eval { $class->configfile };

        # this is gross, but since a lot of users have swapped in their own
        # default subs, we have to keep calling it rather than calling a
        # builder sub directly - and it might not even be a coderef either
        my $cfmeta = $class->meta->find_attribute_by_name('configfile');
        $configfile = $cfmeta->default if not defined $configfile and $cfmeta->has_default;

        if (ref $configfile eq 'CODE') {
            $configfile = $configfile->($class);
        }

        my $init_arg = $cfmeta->init_arg;
        $opts{$init_arg} = $configfile if defined $configfile and defined $init_arg;
    }

    if (defined $configfile) {
        my $hash = $class->get_config_from_file($configfile);

        no warnings 'uninitialized';
        croak "get_config_from_file($configfile) did not return a hash (got $hash)"
            unless ref $hash eq 'HASH';

        %opts = (%$hash, %opts);
    }

    $class->new(\%opts);
}

sub get_config_from_file {
  my ($class, $file) = @_;
  open my $in_fh, '<', $file;
  my $cleaned_txt;
  while (<$in_fh>)
  {
    chomp $_;
    if ($_ =~ /\A#/)
    {
      say "ignoring comment in $file: $_";
    }
    elsif ($_ =~ m/\A([\-\=\:\/\t\s\w.]+)\Z/)
    {
      $cleaned_txt .= $1 . "\n";
    }
    elsif ($_ =~ m/\A\s*\Z/)
    {
      say "skipping blank line in $file."
    }
    else
    {
      croak "Bad data in $file: $_\n";
    }
  }
  my $opt_href = Load($cleaned_txt);
  return $opt_href;
}

=head1 AUTHOR

Thomas Wingo, C<< <thomas.wingo at emory.edu> >>

=head1 BUGS

Please report any bugs or feature requests to C<bug-seq at rt.cpan.org>, or through
the web interface at L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=Seq>.  I will be notified, and then you'll
automatically be notified of progress on your bug as I make changes.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc Seq::Config


You can also look for information at:

=over 4

=item * RT: CPAN's request tracker (report bugs here)

L<http://rt.cpan.org/NoAuth/Bugs.html?Dist=Seq>

=item * AnnoCPAN: Annotated CPAN documentation

L<http://annocpan.org/dist/Seq>

=item * CPAN Ratings

L<http://cpanratings.perl.org/d/Seq>

=item * Search CPAN

L<http://search.cpan.org/dist/Seq/>

=back


=head1 ACKNOWLEDGEMENTS


=head1 LICENSE AND COPYRIGHT

Copyright 2015 Thomas Wingo.

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program.  If not, see L<http://www.gnu.org/licenses/>.


=cut

no Moose::Role; 1; # End of Seq::Config
