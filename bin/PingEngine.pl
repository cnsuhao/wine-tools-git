#!/usr/bin/perl -Tw
#
# Ping WineTestBot engine to see if it is alive
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
use lib "/usr/lib/winetestbot/lib";

require "Config.pl";

use WineTestBot::Engine::Notify;

my $EngineRunning = PingEngine();
if (! defined($ARGV[0]) || $ARGV[0] ne "-q")
{
  print "WineTestBot engine is ", $EngineRunning ? "alive" : "dead", "\n";
}

exit ($EngineRunning ? 0 : 1);
