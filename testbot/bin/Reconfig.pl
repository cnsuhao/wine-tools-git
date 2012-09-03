#!/usr/bin/perl -Tw
#
# Performs the 'reconfig' task in the build machine. Specifically this updates
# the build machine's Wine repository, re-runs configure, and rebuilds the
# 32 and 64 bit winetest binaries.
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

my $Dir;
sub BEGIN
{
  $0 =~ m=^(.*)/[^/]*$=;
  $Dir = $1;
}
use lib "$Dir/../lib";

use WineTestBot::Config;

sub LogMsg
{
  my $oldumask = umask(002);
  if (open LOGFILE, ">>$LogDir/Reconfig.log")
  {
    print LOGFILE "Reconfig: ", @_;
    close LOGFILE;
  }
  umask($oldumask);
}

sub FatalError
{
  LogMsg @_;

  exit 1;
}

sub GitPull
{
  system("cd $DataDir/wine-git && git pull >> $LogDir/Reconfig.log 2>&1");
  if ($? != 0)
  {
    LogMsg "Git pull failed\n";
    return !1;
  }

  return 1;
}

sub BuildNative
{
  system("cd $DataDir/build-native && " .
         "rm -rf * && " .
         "../wine-git/configure --enable-win64 --without-x --without-freetype " .
         ">> $LogDir/Reconfig.log 2>&1 &&" .
         "make depend >> $LogDir/Reconfig.log 2>&1 &&" .
         "make __tooldeps__ >> $LogDir/Reconfig.log 2>&1");

  if ($? != 0)
  {
    LogMsg "Build native failed\n";
    return !1;
  }

  return 1;
}

sub BuildCross
{
  my $Bits = $_[0];

  my $Host = ($Bits == 64 ? "x86_64-w64-mingw32" : "i686-pc-mingw32");
  system("cd $DataDir/build-mingw$Bits && " .
         "rm -rf * && " .
         "../wine-git/configure --host=$Host --with-wine-tools=../build-native " .
         "--without-x --without-freetype >> $LogDir/Reconfig.log 2>&1 &&" .
         "make depend >> $LogDir/Reconfig.log 2>&1 &&" .
         "make programs/winetest >> $LogDir/Reconfig.log 2>&1");
  if ($? != 0)
  {
    LogMsg "Build cross ($Bits bits) failed\n";
    return !1;
  }

  return 1;
}

$ENV{PATH} = "/usr/bin:/bin:/usr/local/mingw/bin:/usr/local/mingw64/bin";
delete $ENV{ENV};

# Start with clean logfile
unlink("$LogDir/Reconfig.log");

if (! GitPull())
{
  exit(1);
}

if (! BuildNative())
{
  exit(1);
}

if (! BuildCross(32) || ! BuildCross(64))
{
  exit(1);
}

LogMsg "ok\n";
exit;
