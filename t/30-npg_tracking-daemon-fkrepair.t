use strict;
use warnings;
use Test::More tests => 8;
use Cwd;

use_ok('npg_tracking::daemon::fkrepair');
{
  my $r = npg_tracking::daemon::fkrepair->new();
  isa_ok($r, 'npg_tracking::daemon::fkrepair');
}

{
  my $command = 'npg_mlwarehouse_fkrepair';
  my $log_dir = join(q[/],getcwd(), 'logs');
  my $r = npg_tracking::daemon::fkrepair->new(timestamp => '2013');
  is(join(q[ ], @{$r->hosts}), q[sf2-farm-srv2], 'default host names array');
  is($r->command, "$command --loop --sleep_time 1200", 'command to run');
  is($r->daemon_name, $command, 'daemon name');

  my $host = q[sf-1-1-01];
  my $test = q{[[ -d } . $log_dir . q{ && -w } . $log_dir . q{ ]] && };
  my $error = q{ || echo Log directory } .  $log_dir . q{ for staging host } . $host . q{ cannot be written to};
  my $action = $test . qq[daemon -i -r -a 10 -n $command --umask 002 -A 10 -L 10 -M 10 -o $log_dir/$command-$host-2013.log -- $command --loop --sleep_time 1200] . $error;

  is($r->start($host), $action, 'start command');
  is($r->ping, qq|daemon --running -n $command && ((if [ -w /tmp/${command}.pid ]; then touch -mc /tmp/${command}.pid; fi)| . q[ && echo -n 'ok') || echo -n 'not ok'], 'ping command');
  is($r->stop, qq[daemon --stop -n $command], 'stop command');
}

1;
