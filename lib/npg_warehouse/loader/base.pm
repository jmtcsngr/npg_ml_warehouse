package npg_warehouse::loader::base;

use Moose;

use WTSI::DNAP::Warehouse::Schema;
use npg_tracking::Schema;
use npg_qc::Schema;

our $VERSION  = '0';

=head1 NAME

npg_warehouse::loader::base

=head1 SYNOPSIS

  package mypackage;
  use Moose;
  extends 'npg_warehouse::loader::base';

=head1 DESCRIPTION

A base class for warehouse-related code. Defines common attributes.

=head1 SUBROUTINES/METHODS

=head2 explain

Boolean flag activating logging of linking to the flowcell table problems

=cut
has 'explain'      => ( isa           => 'Bool',
                        is            => 'ro',
                        required      => 0,
                        default       => 0,
                        documentation =>
  'Boolean flag, activates logging of linking to the flowcell table' .
  ' problems, false by default',
);

=head2 verbose

Verbose boolean flag

=cut
has 'verbose'      => ( isa           => 'Bool',
                        is            => 'ro',
                        required      => 0,
                        default       => 0,
                        documentation =>
  'Verbose boolean flag, false by default',
);

=head2 schema_wh

DBIx schema object for the warehouse database

=cut
has 'schema_wh'  =>  ( isa        => 'WTSI::DNAP::Warehouse::Schema',
                       is         => 'ro',
                       required   => 0,
                       lazy_build => 1,
);
sub _build_schema_wh {
  return WTSI::DNAP::Warehouse::Schema->connect();
}

=head2 schema_npg

DBIx schema object for the npg database

=cut
has 'schema_npg' =>  ( isa        => 'npg_tracking::Schema',
                       is         => 'ro',
                       required   => 0,
                       lazy_build => 1,
);
sub _build_schema_npg {
  return npg_tracking::Schema->connect();
}

=head2 schema_qc

DBIx schema object for the NPG QC database

=cut
has 'schema_qc' =>   ( isa        => 'npg_qc::Schema',
                       is         => 'ro',
                       required   => 0,
                       lazy_build => 1,
);
sub _build_schema_qc {
  return npg_qc::Schema->connect();
}

__PACKAGE__->meta->make_immutable;

1;

__END__


=head1 DIAGNOSTICS

=head1 CONFIGURATION AND ENVIRONMENT

=head1 DEPENDENCIES

=over

=item Moose

=item WTSI::DNAP::Warehouse::Schema

=item npg_tracking::Schema

=item npg_qc::Schema

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
