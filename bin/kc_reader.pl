use 5.10.0;
use warnings;
use strict;
use KyotoCabinet;
use Cpanel::JSON::XS;

# create the database object
my $db = new KyotoCabinet::DB;

# open the database
if (!$db->open('casket.kch', $db->OREADER ) ) {
    printf STDERR ("open error: %s\n", $db->error);
}

# traverse records
my $cur = $db->cursor;
$cur->jump;
while (my ($key, $value) = $cur->get(1)) {
  say $key, decode_json $value;
}
$cur->disable;

# close the database
if (!$db->close) {
    printf STDERR ("close error: %s\n", $db->error);
}
