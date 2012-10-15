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

package WineTestBot::Log;

=head1 NAME

WineTestBot::Log - Logging

=cut

use WineTestBot::Config;

use vars qw (@ISA @EXPORT);

require Exporter;
@ISA = qw(Exporter);
@EXPORT = qw(&LogMsg);

my $logfile;
sub LogMsg(@)
{
  if (!defined $logfile)
  {
    my $oldumask = umask(002);
    if (!open($logfile, ">>", "$LogDir/log"))
    {
      require File::Basename;
      print STDERR File::Basename::basename($0), ":warning: could not open '$LogDir/log' for writing: $!\n";
      open($logfile, ">>&=", 2);
    }
    umask($oldumask);

    # Flush after each print
    my $tmp=select($logfile);
    $| = 1;
    select($tmp);
  }
  print $logfile scalar localtime, " ", @_ if ($logfile);
}

1;
