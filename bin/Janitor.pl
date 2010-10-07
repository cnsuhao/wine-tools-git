#!/usr/bin/perl -Tw
#
# Janitorial tasks
# Run this from crontab once per day, e.g.
# 17 1 * * * /usr/lib/winetestbot/bin/Janitor.pl
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
use WineTestBot::Jobs;
use WineTestBot::Log;
use WineTestBot::Patches;
use WineTestBot::PendingPatchSets;

$ENV{PATH} = "/usr/bin:/bin";
delete $ENV{ENV};

if ($WineTestBot::Config::JobPurgeDays != 0)
{
  my $DeleteBefore = time() - $WineTestBot::Config::JobPurgeDays * 86400;
  my $Jobs = CreateJobs();
  foreach my $JobKey (@{$Jobs->GetKeys()})
  {
    my $Job = $Jobs->GetItem($JobKey);
    if (defined($Job->Ended) && $Job->Ended < $DeleteBefore)
    {
      LogMsg "Janitor: deleting job ", $Job->Id, "\n";
      system "rm", "-rf", "$DataDir/jobs/" . $Job->Id;
      my $ErrMessage = $Jobs->DeleteItem($Job);
      if (defined($ErrMessage))
      {
        LogMsg "Janitor: ", $ErrMessage, "\n";
      }
    }
  }
  $Jobs = undef;
}

my $DeleteBefore = time() - 1 * 86400;
my $Sets = WineTestBot::PendingPatchSets::CreatePendingPatchSets();
foreach my $SetKey (@{$Sets->GetKeys()})
{
  my $Set = $Sets->GetItem($SetKey);
  my $Parts = $Set->Parts;
  my $MostRecentPatch;
  foreach my $PartKey (@{$Parts->GetKeys()})
  {
    my $Patch = $Parts->GetItem($PartKey)->Patch;
    if (! defined($MostRecentPatch) ||
        $MostRecentPatch->Received < $Patch->Received)
    {
      $MostRecentPatch = $Patch;
    }
  }
  if (! defined($MostRecentPatch) ||
      $MostRecentPatch->Received < $DeleteBefore)
  {
    LogMsg "Janitor: deleting pending series for ", $Set->EMail, "\n";
    $Sets->DeleteItem($Set);
    $MostRecentPatch->Disposition("Incomplete series, discarded");
    $MostRecentPatch->Save();
  }
}

if ($WineTestBot::Config::JobPurgeDays != 0)
{
  $DeleteBefore = time() - 7 * 86400;
  my $Patches = CreatePatches();
  foreach my $PatchKey (@{$Patches->GetKeys()})
  {
    my $Patch = $Patches->GetItem($PatchKey);
    if ($Patch->Received < $DeleteBefore)
    {
      my $Jobs = CreateJobs();
      $Jobs->AddFilter("Patch", [$Patch]);
      if ($Jobs->IsEmpty())
      {
        LogMsg "Janitor: deleting patch ", $Patch->Id, "\n";
        unlink("$DataDir/patches/" . $Patch->Id);
        my $ErrMessage = $Patches->DeleteItem($Patch);
        if (defined($ErrMessage))
        {
          LogMsg "Janitor: ", $ErrMessage, "\n";
        }
      }
    }
  }
  $Patches = undef;
}
