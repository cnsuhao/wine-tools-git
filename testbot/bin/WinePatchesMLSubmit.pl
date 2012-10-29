#!/usr/bin/perl -Tw
#
# This script expects to receive a wine-patches email on stdin and submits it
# to WineTestBot for testing. It is meant to be called from a tool such as
# procmail.
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

sub BEGIN
{
  if ($0 =~ m=^(.*)/[^/]+/[^/]+$=)
  {
    $::RootDir = $1;
    unshift @INC, "$::RootDir/lib";
  }
}

use File::Copy;
use WineTestBot::Config;
use WineTestBot::Utils;
use WineTestBot::Engine::Notify;

# Store the message in the staging dir
my $FileNameRandomPart = GenerateRandomString(32);
while (-e ("$DataDir/staging/${FileNameRandomPart}_wine-patches"))
{
  $FileNameRandomPart = GenerateRandomString(32);
}
copy(\*STDIN, "$DataDir/staging/${FileNameRandomPart}_wine-patches");

# Let the engine handle it
WinePatchMLSubmission("${FileNameRandomPart}_wine-patches");

exit 0;
