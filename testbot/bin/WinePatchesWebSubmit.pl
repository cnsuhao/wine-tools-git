#!/usr/bin/perl -Tw
#
# Retrieve the latest patches from the patches website and submit them for
# testing.
#
# Copyright 2009 Ge van Geldorp
# Copyright 2013 Francois Gouget
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
  if ($0 !~ m=^/=)
  {
    # Turn $0 into an absolute path so it can safely be used in @INC
    require Cwd;
    $0 = Cwd::cwd() . "/$0";
  }
  if ($0 =~ m=^(/.*)/[^/]+/[^/]+$=)
  {
    $::RootDir = $1;
    unshift @INC, "$::RootDir/lib";
  }
}

use File::Copy;
use WineTestBot::Config;
use WineTestBot::Log;
use WineTestBot::Utils;
use WineTestBot::Patches;
use WineTestBot::Engine::Notify;

my ($MaxCount) = @ARGV;
if (defined $MaxCount)
{
  $MaxCount =~ m/^(\d+)$/;
  $MaxCount = $1;
}

my $LastWebPatchId = 0;
foreach my $Patch (@{CreatePatches()->GetItems()})
{
  my $WebPatchId = $Patch->WebPatchId;
  if (defined $WebPatchId and $LastWebPatchId < $WebPatchId)
  {
    $LastWebPatchId = $WebPatchId;
  }
}

while (1)
{
  $LastWebPatchId++;
  my $NewPatch = "$DataDir/webpatches/$LastWebPatchId";
  last if (!-f $NewPatch);

  my $FileNameRandomPart = GenerateRandomString(32);
  while (-e "$DataDir/staging/${FileNameRandomPart}_patch_$LastWebPatchId")
  {
    $FileNameRandomPart = GenerateRandomString(32);
  }
  my $StagingFileName = "$DataDir/staging/${FileNameRandomPart}_patch_$LastWebPatchId";

  if (!copy($NewPatch, $StagingFileName))
  {
    LogMsg "Unable to copy '$NewPatch' to '$StagingFileName': $!\n";
    exit 1;
  }

  WinePatchWebSubmission("${FileNameRandomPart}_patch_$LastWebPatchId", $LastWebPatchId);
  LogMsg "Added wine-patches patch $LastWebPatchId\n";
  if (defined $MaxCount)
  {
    $MaxCount--;
    last if ($MaxCount == 0);
  }
}

exit;
