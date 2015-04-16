package npg_warehouse::fk_repair;

use Moose;
use MooseX::StrictConstructor;
use Try::Tiny;
use Log::Log4perl qw(:easy);
use Readonly;
use Carp;

use npg_warehouse::loader::run;

extends 'npg_warehouse::loader::base';
with    'MooseX::Getopt';

our $VERSION = '0';

Readonly::Scalar my $WAIT_HOURS          => q[wait_hours];
Readonly::Scalar my $LAST_TRIED          => q[last_tried];
Readonly::Scalar my $SLEEP_TIME          => 300;
Readonly::Scalar my $MAX_WAIT_HOURS      => 256;
Readonly::Scalar my $WAIT_HOURS_MULTIPLE => 4;

=head1 NAME

npg_warehouse::fk_repair

=head1 SYNOPSIS

 npg::warehouse::fk_repair->new()->run();
 npg::warehouse::fk_repair->new(loop => 1)->run();

=head1 DESCRIPTION

Sets (repairs)  NULL foreign keys from iseq_product_metrics
table to iseq_flowcell table.
Invokes ml warehouse loader npg_warehouse::loader::run
to repair individual runs.

=head1 SUBROUTINES/METHODS

=head2 verbose

=head2 explain

=head2 schema_wh

=head2 schema_npg

=head2 schema_qc

=cut

has [qw/ +schema_wh +schema_npg +schema_qc /] => (metaclass => 'NoGetopt',);

=head2 loop

Boolean flag. If true, the repair loops indefinitely with
sleep_time periods of inactivity. False by default, i.e.
only one repair attempt is made.

=cut

has 'loop'         =>   ( isa           => 'Bool',
                          is            => 'ro',
                          required      => 0,
                          default       => 0,
                          documentation =>
  q[Boolean flag. If true, the repair loops indefinitely with] .
  q[ sleep_time periods of inactivity. False by default, i.e.].
  q[ only one repair attempt is made.],
);

=head2 sleep_time

Duration of inactivity period in seconds.

=cut

has 'sleep_time'   =>   ( isa        => 'Int',
                          is         => 'ro',
                          required   => 0,
                          lazy_build => 1,
                          documentation =>
  q[Duration of inactivity period in seconds. Defaults to ] .
  $SLEEP_TIME . q[ if loop is true, to zero if loop is false.],
);
sub _build_sleep_time {
  my $self = shift;
  return $self->loop ? $SLEEP_TIME : 0;
}

has '_logger'      =>   ( isa        => 'Log::Log4perl::Logger',
                          is         => 'ro',
                          required   => 0,
                          lazy_build => 1,
);
sub _build__logger {
  Log::Log4perl->easy_init($INFO);
  return Log::Log4perl->get_logger();
}

has '_pmrs'        =>   ( isa        => 'DBIx::Class::ResultSet',
                          is         => 'ro',
                          required   => 0,
                          lazy_build => 1,
);
sub _build__pmrs {
  my $self = shift;
  return $self->schema_wh->resultset('IseqProductMetric');
}

has '_history'     =>   ( isa        => 'HashRef',
                          is         => 'ro',
                          required   => 0,
                          default    => sub { return {}; },
);

sub _where_query {
  my $h = {};
  $h->{'id_iseq_flowcell_tmp'} = undef;
  $h->{'tag_index'}            = [undef, {q[!=], 0}];
  return $h;
}

sub _runs_with_null_fks {
  my $self = shift;
  my @runs = sort { $a <=> $b } map {$_->id_run} $self->_pmrs->search(
       $self->_where_query(),
       {columns   => 'id_run', distinct  => 1}
     );
  return @runs;
}

sub _all_fks_set {
  my ($self, $id) = @_;

  if (!$id) {
    croak 'Run id should be provided';
  }
  my $query = $self->_where_query();
  $query->{'id_run'} = $id;
  return !$self->_pmrs->search($query)->count();
}

sub _do_repair {
  my ($self, $id, $now) = @_;

  if (!$id) {
    croak 'Run id should be provided';
  }
  if (!$now) {
    croak 'Time now should be provided';
  }

  my $wait_hash  = $self->_history->{$id};
  my $do_repair = 1;
  if ($wait_hash) {
    my $diff_hours =
      $now->subtract_datetime($wait_hash->{$LAST_TRIED})->in_units('hours');
    $do_repair =  $diff_hours >= $wait_hash->{$WAIT_HOURS};
  }

  return $do_repair;
}

=head2 run

Runs repair. Loops indefinitely with sleep_time periods of inactivity.
False by default, i.e. only one repair attempt is made.

=cut

sub run {
  my $self = shift;

  ##no critic (ControlStructures::ProhibitPostfixControls)
  do { # run at least once
    $self->_run_once(DateTime->now());
    sleep($self->sleep_time);
  } while ( $self->loop ); # boolean loop condition

  return;
}

sub _run_once {
  my ($self, $now) = @_;

  foreach my $id ($self->_runs_with_null_fks()) {
    if (!$self->_do_repair($id, $now)) {
      $self->_logger->info(qq[Skipping repair for run $id]);
      next;
    }
    $self->_logger->info(qq[Calling loader for run $id]);

    my $loader = npg_warehouse::loader::run->new(
      verbose    => $self->verbose,
      explain    => $self->explain,
      id_run     => $id,
      schema_npg => $self->schema_npg,
      schema_qc  => $self->schema_qc,
      schema_wh  => $self->schema_wh,
    );
    $loader->load();

    if ($self->_all_fks_set($id)) {
      $self->_logger->warn(qq[Repaired foreign keys for run $id]);
      delete $self->_history->{$id};
    } else {
      $self->_logger->warn(qq[Failed to repair foreign keys for run $id]);
      my $wait_hours = $self->_history->{$id}->{$WAIT_HOURS} || 1;
      $self->_history->{$id}->{$WAIT_HOURS} =
        $wait_hours >= $MAX_WAIT_HOURS ? $wait_hours : $wait_hours * $WAIT_HOURS_MULTIPLE;
      $self->_history->{$id}->{$LAST_TRIED} = $now;
    }
  }

  return;
}

__PACKAGE__->meta->make_immutable;

1;

__END__


=head1 DIAGNOSTICS

=head1 CONFIGURATION AND ENVIRONMENT

=head1 DEPENDENCIES

=over

=item Carp

=item Readonly

=item Try::Tiny

=item Log::Log4perl

=item Moose

=item MooseX::StrictConstructor

=item MooseX::Getopt

=back

=head1 INCOMPATIBILITIES

=head1 BUGS AND LIMITATIONS

=head1 AUTHOR

Marina Gourtovaia

=head1 LICENSE AND COPYRIGHT

Copyright (C) 2015 Genome Research Limited

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program.  If not, see <http://www.gnu.org/licenses/>.

=cut
