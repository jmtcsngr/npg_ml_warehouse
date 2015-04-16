use strict;
use warnings;
use Test::More tests => 22;
use Test::Exception;
use Moose::Meta::Class;
use File::Temp qw/tempdir/;
use File::Copy;

use npg_testing::db;

use npg_qc::autoqc::qc_store;

my $RUN_LANE_TABLE_NAME      = q[IseqRunLaneMetric];
my $PRODUCT_TABLE_NAME       = q[IseqProductMetric];
my $LIMS_FK_COLUMN_NAME      = q[id_iseq_flowcell_tmp];

use_ok ('npg_warehouse::fk_repair');
isa_ok (npg_warehouse::fk_repair->new(), 'npg_warehouse::fk_repair');

{
  my $r = npg_warehouse::fk_repair->new();
  ok(!$r->loop, 'loop is false by default');
  ok(!$r->verbose, 'verbose is false by default');
  ok(!$r->explain, 'explain is false by default');
  is($r->sleep_time, 0, 'sleep time is zero by default');

  $r = npg_warehouse::fk_repair->new(loop => 1);
  ok($r->loop, 'loop is set to true');
  is($r->sleep_time, 300, 'sleep time is set to 300');

  $r = npg_warehouse::fk_repair->new(loop => 1, sleep_time => 120);
  ok($r->loop, 'loop is set to true');
  is($r->sleep_time, 120, 'sleep time is set to 120');
}

my $util = Moose::Meta::Class->create_anon_class(
  roles => [qw/npg_testing::db/])->new_object({});

# Get full (lim sand npg) set of fixtures
my $wh_fix = tempdir(UNLINK => 0);
foreach my $dir (qw(t/data/fixtures/wh t/data/fixtures/wh_npg)) {
  foreach my $file (glob join(q[/], $dir, '*.yml')) {
    copy $file, $wh_fix;
  }
}

my ($schema_npg, $schema_qc, $schema_wh);

lives_ok{ $schema_wh  = $util->create_test_db(q[WTSI::DNAP::Warehouse::Schema],
  $wh_fix) } 'warehouse test db created';
lives_ok{ $schema_npg  = $util->create_test_db(q[npg_tracking::Schema],
  q[t/data/fixtures/npg]) } 'npg test db created';
lives_ok{ $schema_qc  = $util->create_test_db(q[npg_qc::Schema],
  q[t/data/fixtures/npgqc]) } 'npgqc test db created';

{
  my $init = {
       schema_npg   => $schema_npg, 
       schema_qc    => $schema_qc, 
       schema_wh    => $schema_wh,
       verbose      => 0,
       explain      => 0,
       loop         => 0,
             };

  my $rs = $schema_wh->resultset('IseqProductMetric');
  my @lanes = sort map {$_->position}
    $rs->search({id_run               => 4486,
                 id_iseq_flowcell_tmp => undef,
                 tag_index            => [undef, {'!=', 0}],
                })->all;
  is (join(q[:], @lanes), '3:4:5', 'lanes without fk - test prerequisite');

  my $total       = $rs->search({id_run => 6998})->count;
  my $no_fk_count = $rs->search({id_run => 6998, id_iseq_flowcell_tmp => undef})->count;
  is ($no_fk_count, $total, 'no record for run 6998 has fk - test prerequisite');

  my $r = npg_warehouse::fk_repair->new($init);
  is (join(q[ ], $r->_runs_with_null_fks()) , '4486 6998', 'runs to repair detected');
  lives_ok {$r->run()} 'repair runs OK';
  is (join(q[ ], $r->_runs_with_null_fks()) , '4486', 'runs to repair are still detected');

  my $no_fk_rs = $rs->search({id_run => 4486, id_iseq_flowcell_tmp => undef});
  is ($no_fk_rs->count, 2,
    'two rows for run 4486 are without the fk (lim sdata missing for lane 5)');
  @lanes = sort map {$_->position} $no_fk_rs->all;
  is (join(q[ ], @lanes), '1 5', 'no fk for lanes 1 and 5');

  $no_fk_rs = $rs->search({id_run => 6998, id_iseq_flowcell_tmp => undef});
  my $tags = { };
  $tags->{'tag_index0'} = 0;
  map { $tags->{'tag_index' . $_->tag_index} += 1 } $no_fk_rs->all();
  is (scalar keys %{$tags}, 1, 'only one type of tag cannot be linked to lims');
  is ($tags->{'tag_index0'}, 6, 'six tag zero records cannot be linked to lims');
}

1;
