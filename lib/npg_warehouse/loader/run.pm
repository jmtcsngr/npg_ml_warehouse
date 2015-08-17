package npg_warehouse::loader::run;

use Moose;
use MooseX::StrictConstructor;
use Try::Tiny;
use List::MoreUtils qw/ any none /;
use Readonly;
use Carp;

use npg_qc::autoqc::qc_store;

use npg_warehouse::loader::autoqc;
use npg_warehouse::loader::qc;
use npg_warehouse::loader::npg;

extends 'npg_warehouse::loader::base';

with qw/
   npg_tracking::glossary::run
   npg_tracking::glossary::flowcell
       /;
with 'WTSI::DNAP::Warehouse::Schema::Query::IseqFlowcell';

our $VERSION  = '0';

Readonly::Scalar my $NON_INDEXED_LIBRARY      => $WTSI::DNAP::Warehouse::Schema::Query::IseqFlowcell::NON_INDEXED_LIBRARY;
Readonly::Scalar my $CONTROL_LANE             => $WTSI::DNAP::Warehouse::Schema::Query::IseqFlowcell::CONTROL_LANE;
Readonly::Scalar my $INDEXED_LIBRARY          => $WTSI::DNAP::Warehouse::Schema::Query::IseqFlowcell::INDEXED_LIBRARY;
Readonly::Scalar my $INDEXED_LIBRARY_SPIKE    => $WTSI::DNAP::Warehouse::Schema::Query::IseqFlowcell::INDEXED_LIBRARY_SPIKE;

Readonly::Scalar my $FLOWCELL_LIMS_TABLE_NAME => q[IseqFlowcell];
Readonly::Scalar my $RUN_LANE_TABLE_NAME      => q[IseqRunLaneMetric];
Readonly::Scalar my $PRODUCT_TABLE_NAME       => q[IseqProductMetric];
Readonly::Scalar my $LIMS_FK_COLUMN_NAME      => q[id_iseq_flowcell_tmp];

Readonly::Scalar my $FORWARD_END_INDEX        => 1;
Readonly::Scalar my $REVERSE_END_INDEX        => 2;
Readonly::Scalar my $PLEXES_KEY               => q[plexes];

Readonly::Scalar my $SPIKE_FALLBACK_TAG_INDEX => 888;
Readonly::Scalar my $MIN_NEW_RUN              => 10_000;

=head1 NAME

npg_warehouse::loader::run

=head1 SYNOPSIS

 npg::warehouse::loader::run->new(id_run => 4444)->load;

=head1 DESCRIPTION

=head1 SUBROUTINES/METHODS

=head2 id_run

Run id

=head2 id_flowcell_lims

LIMs specific flowcell id

=cut
has '+id_flowcell_lims'  => ( lazy_build => 1,);
sub _build_id_flowcell_lims {
  my $self = shift;
  return $self->_run_lane_rs->[0]->run->batch_id;
}

=head2 id_flowcell_manufacturer

Manufacturer flowcell id

=cut
has '+flowcell_barcode'  => ( lazy_build => 1,);
sub _build_flowcell_barcode {
  my $self = shift;
  return $self->_run_lane_rs->[0]->run->flowcell_id;
}

=head2 iseq_flowcell

DBIx result set from which relevant flowcell rows can be retrieved

=cut
sub iseq_flowcell {
  my $self = shift;
  return $self->schema_wh->resultset($FLOWCELL_LIMS_TABLE_NAME);
}

has ['_rlt_column_names', '_pt_column_names'] =>  (
                           isa        => 'ArrayRef',
                           is         => 'ro',
                           required   => 0,
                           lazy_build => 1,
);
sub _column_names {
  my ($self, $table) = @_;
  my @columns = $self->schema_wh->resultset($table)->result_source->columns();
  return \@columns;
}
sub _build__rlt_column_names {
  my $self = shift;
  return $self->_column_names($RUN_LANE_TABLE_NAME);
}
sub _build__pt_column_names {
  my $self = shift;
  return $self->_column_names($PRODUCT_TABLE_NAME);
}

has '_flowcell_table_fks' => ( isa        => 'HashRef',
                               is         => 'ro',
                               required   => 0,
                               lazy_build => 1,
);
sub _build__flowcell_table_fks {
  my $self = shift;

  my $fks = {};
  my $rs;
  try {
    $rs = $self->query_resultset;
  } catch {
    my $allowed_error = qr/id_flowcell_lims\sor\sflowcell_barcode/xms;
    my $error = $_;
    if ($error !~ $allowed_error) {
      croak $error;
    }
  };

  if (!$rs) {
    if ($self->explain) {
      warn q[Tracking database has no flowcell information for run ] . $self->id_run . qq[\n];
    }
    return $fks;
  }

  if ($rs && $rs->count) {
    my @to_delete = ();
    while (my $row = $rs->next()) {
      my $entity_type = $row->entity_type;
      my $position    = $row->position;
      my $pt_key = _pt_key($position, $row->tag_index);
      if (exists $fks->{$position}->{$entity_type}->{$pt_key}) {
        warn sprintf 'Run %i: multiple flowcell table records for %s, pt key %s%s',
          $self->id_run, $entity_type, $pt_key, qq[\n];
        push @to_delete, [$position, $entity_type, $pt_key];
      }
      $fks->{$position}->{$entity_type}->{$pt_key} = $row->$LIMS_FK_COLUMN_NAME;
    }
    foreach my $d (@to_delete) {
      delete $fks->{$d->[0]}->{$d->[1]}->{$d->[2]};
    }
  } else {
    if ($self->explain) {
      warn q[Flowcell table has no LIMs information for run ] . $self->id_run . qq[\n];
    }
  }

  return $fks;
}

has '_flowcell_table_fks_exist' => ( isa => 'Bool',
                                     is => 'ro',
                                     required => 0,
                                     lazy_build => 1,
);
sub _build__flowcell_table_fks_exist {
  my $self = shift;
  return scalar keys %{$self->_flowcell_table_fks} ? 1 : 0;
}

=head2 _autoqc_store

A driver to retrieve autoqc objects. If DB storage is not available,
it will give no error, so no need to mock DB for this one in tests.
Just mock the staging area in your tests

=cut
has '_autoqc_store' =>    ( isa        => 'npg_qc::autoqc::qc_store',
                            is         => 'ro',
                            required   => 0,
                            lazy_build => 1,
);
sub _build__autoqc_store {
  my $self = shift;
  return npg_qc::autoqc::qc_store->new(use_db    => 1,
                                       verbose   => $self->verbose,
                                       qc_schema => $self->schema_qc);
}

=head2 _run_lane_rs

Result set object for run lanes that have to be loaded

=cut
has '_run_lane_rs' =>     ( isa        => 'ArrayRef',
                            is         => 'ro',
                            required   => 0,
                            lazy_build => 1,
);
sub _build__run_lane_rs {
  my $self = shift;
  my @all_rs = $self->schema_npg->resultset('RunLane')->search(
    { q[me.id_run] => $self->id_run},
    {
      prefetch => q[run],
      order_by => [q[me.id_run], q[me.position]],
    },
  )->all;
  return \@all_rs;
}

has '_old_forward_id_run'  => ( isa        => 'Int',
                                is         => 'ro',
                                required   => 0,
                                lazy_build => 1,
);
sub _build__old_forward_id_run {
  my $self= shift;
  my $rp = $self->_run_lane_rs->[0]->run->id_run_pair;
  $rp ||= 0;
  return $rp;
}

has '_autoqc_data'   =>   ( isa        => 'HashRef',
                            is         => 'ro',
                            required   => 0,
                            lazy_build => 1,
);
sub _build__autoqc_data {
  my $self = shift;
  if (!$self->_run_is_cancelled) {
    return npg_warehouse::loader::autoqc->new(
      autoqc_store => $self->_autoqc_store,
      verbose => $self->verbose,
      plex_key => $PLEXES_KEY)->retrieve($self->id_run, $self->schema_npg);
  }
  return {};
}


has '_npg_data_retriever'   =>   ( isa        => 'npg_warehouse::loader::npg',
                                   is         => 'ro',
                                   required   => 0,
                                   lazy_build => 1,
);
sub _build__npg_data_retriever {
  my $self = shift;
  return npg_warehouse::loader::npg->new(schema_npg => $self->schema_npg,
                                         verbose    => $self->verbose,
                                         id_run     => $self->id_run);
}

has '_run_is_cancelled'   =>   ( isa        => 'Bool',
                                 is         => 'ro',
                                 required   => 0,
                                 lazy_build => 1,
);
sub _build__run_is_cancelled {
  my $self = shift;
  return $self->_npg_data_retriever->run_is_cancelled();
}

has '_run_is_paired_read'   => ( isa        => 'Bool',
                                 is         => 'ro',
                                 required   => 0,
                                 lazy_build => 1,
);
sub _build__run_is_paired_read {
  my $self = shift;
  return $self->_npg_data_retriever->run_is_paired_read();
}

has '_npgqc_data_retriever'   => ( isa        => 'npg_warehouse::loader::qc',
                                   is         => 'ro',
                                   required   => 0,
                                   lazy_build => 1,
);
sub _build__npgqc_data_retriever {
  my $self = shift;
  return npg_warehouse::loader::qc->new(schema_qc         => $self->schema_qc,
                                        verbose           => $self->verbose,
                                        reverse_end_index => $REVERSE_END_INDEX,
                                        plex_key          => $PLEXES_KEY);
}

has '_run_end_summary'   =>    ( isa        => 'HashRef',
                                 is         => 'ro',
                                 required   => 0,
                                 lazy_build => 1,
);
sub _build__run_end_summary {
  my $self = shift;
  return $self->_npgqc_data_retriever->retrieve_summary(
    $self->id_run, $FORWARD_END_INDEX, $self->_run_lane_rs->[0]->run->is_paired);
}

has '_qyields'           =>    ( isa        => 'HashRef',
                                 is         => 'ro',
                                 required   => 0,
                                 lazy_build => 1,
);
sub _build__qyields {
  my $self = shift;
  return $self->_npgqc_data_retriever->retrieve_yields($self->id_run);
}

has '_cluster_density'   =>    ( isa        => 'HashRef',
                                 is         => 'ro',
                                 required   => 0,
                                 lazy_build => 1,
);
sub _build__cluster_density {
  my $self = shift;
  return $self->_npgqc_data_retriever->retrieve_cluster_density($self->id_run);
}

has '_data'              =>    ( isa        => 'HashRef',
                                 is         => 'ro',
                                 required   => 0,
                                 lazy_build => 1,
);
sub _build__data {
  my ($self) = @_;

  my $array              = [];
  my $product_array      = [];

  my $dates              = $self->_npg_data_retriever()->dates();
  my $instr              = $self->_npg_data_retriever()->instrument_info;

  foreach my $rs (@{$self->_run_lane_rs})  {

    my $position                    = $rs->position;
    my $values = {};
    $values->{'id_run'}             = $self->id_run;
    $values->{'flowcell_barcode'}   = $rs->run->flowcell_id;
    $values->{'position'}           = $position;
    $values->{'cycles'}             = $rs->run->actual_cycle_count;
    $values->{'cancelled'}          = $self->_run_is_cancelled;
    $values->{'paired_read'}        = $self->_run_is_paired_read;
    $values->{'instrument_name'}    = $instr->{'name'};
    $values->{'instrument_model'}   = $instr->{'model'};

    foreach my $event_type (keys %{$dates}) {
      $values->{$event_type} = $dates->{$event_type};
    }

    foreach my $column (keys %{ $self->_cluster_density->{$position} || {} }) {
      $values->{$column} = $self->_cluster_density->{$position}->{$column};
    }

    if (exists $self->_run_end_summary->{$position}->{$FORWARD_END_INDEX}) {
      $values->{'raw_cluster_count'}  =
        $self->_run_end_summary->{$position}->{$FORWARD_END_INDEX}->{'clusters_raw'};
      $values->{'pf_cluster_count'}   =
        $self->_run_end_summary->{$position}->{$FORWARD_END_INDEX}->{'clusters_pf'};
      $values->{'pf_bases'}           =
        $self->_run_end_summary->{$position}->{$FORWARD_END_INDEX}->{'lane_yield'};
      if (exists $self->_run_end_summary->{$position}->{$REVERSE_END_INDEX}) {
        $values->{'pf_bases'}        +=
        $self->_run_end_summary->{$position}->{$REVERSE_END_INDEX}->{'lane_yield'};
      }
    }

    my $lane_is_indexed = $self->_lane_is_indexed($position);
    my $product_values;
    my $plexes = {};

    foreach my $data_hash (($self->_qyields, $self->_autoqc_data)) {
      if ($data_hash->{$position}) {
        _copy_plex_values($plexes, $data_hash, $position);
        foreach my $column (keys %{$data_hash->{$position}}) {
	  $values->{$column} = $data_hash->{$position}->{$column};
          if ( !$lane_is_indexed ) {
            $product_values->{$column} = $data_hash->{$position}->{$column};
	  }
	}
      }
    }

    push @{$array}, $values;
    if ($product_values) {
      $product_values->{'id_run'}    = $self->id_run;
      $product_values->{'position'}  = $position;
      push @{$product_array}, $product_values;
    }

    foreach my $tag_index (keys %{$plexes}) {
      my $plex_values             = $plexes->{$tag_index};
      $plex_values->{'id_run'}    = $self->id_run;
      $plex_values->{'position'}  = $position;
      $plex_values->{'tag_index'} = $tag_index;
      push @{$product_array}, $plex_values;
    }
  }

  return {$RUN_LANE_TABLE_NAME => $array, $PRODUCT_TABLE_NAME => $product_array,};
}

sub _lane_is_indexed {
  my ($self, $position) = @_;
  my $is_indexed = exists $self->_autoqc_data->{$position}->{'tags_decode_percent'};
  if (!$is_indexed) {
    if (scalar keys %{$self->_autoqc_data->{$position}->{$PLEXES_KEY}}) {
      my $message = qq[Plex autoqc data present for lane $position, but no tag decoding data available];
      if ($self->id_run < $MIN_NEW_RUN) { # This run is "old".
        if ($self->verbose) {
          warn qq[$message\n];
        }
        $is_indexed = 1;
      } else {
        croak $message;
      }
    }
  }
  return $is_indexed;
}

sub _pt_key {
  my ($p, $t) = @_;
  return defined $t ? join(q[:], $p, $t) : $p;
}

sub _copy_plex_values {
  my ($destination, $source, $position) = @_;

  if (!exists $source->{$position}->{$PLEXES_KEY}) {
    return;
  }

  foreach my $tag_index (keys %{ $source->{$position}->{$PLEXES_KEY} } ) {
    foreach my $column_name (keys %{ $source->{$position}->{$PLEXES_KEY}->{$tag_index} } ) {
      $destination->{$tag_index}->{$column_name} =
        $source->{$position}->{$PLEXES_KEY}->{$tag_index}->{$column_name};
    }
  }
  return;
}

sub _add_lims_fk {
  my ($self, $values) = @_;

  my $position = $values->{'position'};

  my @types = exists $self->_flowcell_table_fks->{$position} ?
    keys %{ $self->_flowcell_table_fks->{$position} } : ();
  if (!@types) {
    if (scalar keys %{$self->_flowcell_table_fks}) {
      if ($self->verbose) {
        warn "Flowcell table has no information for lane $position run " . $self->id_run . "\n";
      }
    }
    return;
  }

  my $pt_key = _pt_key($position, $values->{'tag_index'});
  my $pk;

  if (!defined $values->{'tag_index'} ) {

    my @lane_types = grep { $_ =~ /^(?: $NON_INDEXED_LIBRARY | $CONTROL_LANE )$/xms } @types;
    if (scalar @lane_types > 1) {
      croak q[Lane cannot be both ] . join q[ and  ], @types;
    }

    if (!@lane_types) {
      my @plexes = keys %{$self->_flowcell_table_fks->{$position}->{$INDEXED_LIBRARY}};
      if (scalar @plexes == 1) {  # one-sample pool,
                                  # which we processed as a library
        $pk = $self->_flowcell_table_fks->{$position}->{$INDEXED_LIBRARY}->{$plexes[0]};
      }
    } else {
      $pk = $self->_flowcell_table_fks->{$position}->{$lane_types[0]}->{$pt_key};
    }

  } else {

    $pk = $self->_flowcell_table_fks->{$position}->{$INDEXED_LIBRARY}->{$pt_key};
    if (!$pk) {
      $pk = $self->_flowcell_table_fks->{$position}->{$INDEXED_LIBRARY_SPIKE}->{$pt_key};
      if (!$pk && $values->{'tag_index'} == $SPIKE_FALLBACK_TAG_INDEX) {
        my @spikes = keys %{$self->_flowcell_table_fks->{$position}->{$INDEXED_LIBRARY_SPIKE}};
        if (scalar @spikes == 1) {
          $pk = $self->_flowcell_table_fks->{$position}->{$INDEXED_LIBRARY_SPIKE}->{$spikes[0]};
	}
      }
    }

  }

  if ($pk) {
    $values->{$LIMS_FK_COLUMN_NAME} = $pk;
  } else {
    $self->_explain_missing($pt_key, $values);
  }

  return;
}

sub _explain_missing {
  my ($self, $pt_key, $values) = @_;
  if ($self->explain) {
    if (!defined $values->{'tag_index'} || $values->{'tag_index'} != 0) {
      my $lib_type = defined $values->{'tag_index'} ? $NON_INDEXED_LIBRARY : $INDEXED_LIBRARY;
      my @keys = keys %{$self->_flowcell_table_fks->{$values->{'position'}}->{$lib_type}};
      my $other_keys = @keys ? join(q[ ], @keys) : 'none';
      warn sprintf 'Flowcell table has no information for pt key %s, run %i; other keys %s%s',
        $pt_key, $self->id_run, $other_keys, qq[\n];
    }
  }
  return;
}

sub _filter_column_names {
  my ($self, $table, $values) = @_;

  my @columns = keys %{$values};
  foreach my $name (@columns) {
    my $old_name = $name;
    my $count = $name =~ s/\Atag_sequence\Z/tag_sequence4deplexing/xms;
    if (!$count) {
      $count = $name =~ s/\Abam_//xms;
    }
    if ($count) {
      $values->{$name} = $values->{$old_name};
      delete $values->{$old_name};
    }
    my @available = $table eq $PRODUCT_TABLE_NAME ?
      @{$self->_pt_column_names} : @{$self->_rlt_column_names};
    if (none {$name eq $_} @available) {
      delete $values->{$name};
    }
  }
  return;
}

sub _load_table {
  my ($self, $table) = @_;

  if (scalar keys $self->_data->{$table} == 0) {
    if ($self->verbose) {
      warn qq[No data for table $table\n];
    }
    return 0;
  }

  my @rows = ();
  foreach my $row (@{$self->_data->{$table}}) {

    $self->_filter_column_names($table, $row);
    my @test = keys %{$row};
    @test = grep { $_ !~ /\Aid_run|position|tag_index\Z/smx } @test;
    if (!@test) { # no useful data
      next;
    }

    if ($table eq $PRODUCT_TABLE_NAME && $self->_flowcell_table_fks_exist) {
      $self->_add_lims_fk($row);
    }

    if ($self->verbose) {
      my $message = defined $row->{'tag_index'} ? q[tag_index ] . $row->{'tag_index'} : q[];
      warn sprintf 'Will create record in table %s for run %i position %i %s%s',
         $table, $self->id_run,  $row->{'position'}, $message, qq[\n];
    }
    push @rows, $row;
  }

  my $rs = $self->schema_wh->resultset($table);

  my $transaction;
  if ($table eq $PRODUCT_TABLE_NAME) {
    $transaction = sub {
      $rs->search({'id_run' => $self->id_run,})->delete();
      # Whithout the assignment this should work as a fast batch load.
      # However, this does not see to work correctly - we got rows with
      # some data missing. The assignment forces the per-row loading,
      # therefore the only advantage of using this notation is not
      # writing a loop.
      my $r = $rs->populate(\@rows);
    };
  } else {
    $transaction = sub {
      map { $rs->update_or_create($_) } @rows;
    };
  }

  $self->schema_wh->txn_do($transaction);

  return scalar @rows;
}

=head2 load

Loads data for one sequencing run to the warehouse

=cut
sub load {
  my ($self) = @_;

  my $id_run = $self->id_run;

  if (! @{$self->_run_lane_rs}) {
    if($self->verbose) {
      warn qq[No lanes for run $id_run, not loading\n];
    }
    return;
  }

  if ($self->_old_forward_id_run) {
    if ($self->verbose) {
      warn sprintf 'Run %i is an old reverse run for %i, not loading.%s',
        $id_run, $self->_old_forward_id_run, qq[\n];
    }
    return;
  }

  if (!$self->_npg_data_retriever->run_ready2load) {
    if($self->verbose) {
      warn qq[Too early to load run $id_run, not loading\n];
    }
    return;
  }

  my $data;
  try {
    $data = $self->_data();
  } catch {
    warn "$_\n";
  };

  if ($data) {

    try {
      foreach my $table (($RUN_LANE_TABLE_NAME, $PRODUCT_TABLE_NAME)) {
        my $count = $self->_load_table($table);
        if ($self->verbose) {
          warn qq[Loaded $count rows to table $table for run $id_run\n];
	}
      }
    } catch {
      my $err = $_;
      if ($err =~ /Rollback failed/sxm) {
        croak $err;
      }
      warn qq[Failed to load run $id_run: $err\n];
    };
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

=item List::MoreUtils

=item Try::Tiny

=item Moose

=item MooseX::StrictConstructor

=item WTSI::DNAP::Warehouse::Schema::Query::IseqFlowcell

=item npg_tracking::glossary::run

=item npg_tracking::glossary::flowcell

=item npg_qc::autoqc::qc_store

=item npg_warehouse::loader::autoqc

=item npg_warehouse::loader::qc

=item npg_warehouse::loader::npg

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
