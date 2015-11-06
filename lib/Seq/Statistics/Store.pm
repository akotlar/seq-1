package Seq::Statistics::Store;

use 5.10.0;
use Moose::Role;
use Cpanel::JSON::XS;

with 'Seq::Role::IO';

requires 'statsRecord';

use namespace::autoclean;

has statsExtension => (
  is => 'rw',
  lazy => 1,
  default => 'json'
);

has statsFH => (
  is       => 'ro',
  lazy     => 1,
  init_arg => undef,
  builder  => 'buildFh',
);

sub storeStats {
  my ($self, $outBasePath) = shift;
  if(!@{keys %{$self->statsRecord} } ) {
    $self->tee_logger('warn', 'Trying to save empty stats record');
    return;
  }
  my $fh = $self->_buildFh($outBasePath.'.'.$self->statsExtension);
  print $fh encode_json($self->statsRecord);
}

sub _buildFh {
  my ($self, $outPath) = shift;

  if(!defined $outPath) {
    $self->tee_logger('error', 'no path provided to storeStats'); #programmer error
  } elsif(!$outPath) {
    return \*STDOUT;
  }

  # can't use is_file or is_dir check before file made, unless it alraedy exists
  return $self->get_write_bin_fh($outPath);
}

no Moose::Role;
1;