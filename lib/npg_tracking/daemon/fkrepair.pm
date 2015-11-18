package npg_tracking::daemon::fkrepair;

use Moose;
use Readonly;

extends 'npg_tracking::daemon';

our $VERSION = '0';

Readonly::Scalar our $SCRIPT_NAME => q[npg_mlwarehouse_fkrepair];

override '_build_hosts' => sub { return ['sf2-farm-srv2']; };

override 'daemon_name'  => sub { return $SCRIPT_NAME; };
override 'command'      => sub { return "$SCRIPT_NAME --loop --sleep_time 1200"; };

no Moose;

1;
__END__

=head1 NAME

npg_tracking::daemon::fkrepair

=head1 SYNOPSIS

=head1 DESCRIPTION

 Daemon definition for the script reparing foregn keys in ml warehouse.
 Sleep time between loops is set to 20 minuts.

=head1 SUBROUTINES/METHODS

=head1 DIAGNOSTICS

=head1 CONFIGURATION AND ENVIRONMENT

=head1 DEPENDENCIES

=over

=item Moose

=item Readonly

=item npg_tracking::daemon

=back

=head1 INCOMPATIBILITIES

=head1 BUGS AND LIMITATIONS

=head1 AUTHOR

 Marina Gourtovaia E<lt>mg8@sanger.ac.ukE<gt>

=head1 LICENSE AND COPYRIGHT

Copyright (C) 2015 Genome Research Ltd

This file is part of NPG software.
NPG is free software: you can redistribute it and/or modify
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

