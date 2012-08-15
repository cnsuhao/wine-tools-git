# WineTestBot logging
#
# Copyright 2009 Ge van Geldorp
#
# This library is free software; you can redistribute it and/or
# modify it under the terms of the GNU Lesser General Public
# License as published by the Free Software Foundation; either
# version 2.1 of the License, or (at your option) any later version.
#
# This library is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
# Lesser General Public License for more details.
#
# You should have received a copy of the GNU Lesser General Public
# License along with this library; if not, write to the Free Software
# Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA 02110-1301, USA

use strict;

=head1 NAME

WineTestBot::Log - Logging

=cut

package WineTestBot::Log;

use WineTestBot::Config;

use vars qw (@ISA @EXPORT);

require Exporter;
@ISA = qw(Exporter);
@EXPORT = qw(&LogMsg);

sub LogMsg
{
  my $oldumask = umask(002);
  my $LOGFILE;
  if (open LOGFILE, ">>$LogDir/log")
  {
    print LOGFILE scalar localtime, " ", @_;
    close LOGFILE;
  }
  umask($oldumask);
}

1;
