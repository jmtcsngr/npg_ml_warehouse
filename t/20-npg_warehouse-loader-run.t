use strict;
use warnings;
use Test::More tests => 12;
use Test::Exception;
use Moose::Meta::Class;

use npg_testing::db;
use npg_tracking::Schema;
use npg_qc::Schema;

my @runs = (1, 1937, 4950, 5316, 5970, 6566, 6589, 6857, 7110, 8398, 8284);
my $num_tests = scalar @runs;
$num_tests++;

SKIP: {

  eval {
    npg_tracking::Schema->connect();
    1;
  } or do {
    skip "Failed to connect to NPG DB : $@", $num_tests;
  };
  eval {
    npg_qc::Schema->connect();
    1;
  } or do {
    skip "Failed to connect to NPGQC DB : $@", $num_tests;
  };

  my $util = Moose::Meta::Class->create_anon_class(
    roles => [qw/npg_testing::db/])->new_object({});
  my $schema_wh = $util->create_test_db(q[WTSI::DNAP::Warehouse::Schema]);
  $schema_wh or die 'Failed to created warehouse test database';

  use_ok('npg_warehouse::loader::run');

  foreach my $id_run (@runs) {
    lives_ok {npg_warehouse::loader::run->new( 
                      schema_wh => $schema_wh,
                      verbose    => 0,
                      id_run     => $id_run)->load(); } "run $id_run loaded";

  }
}

1;