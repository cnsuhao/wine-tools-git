#!/usr/bin/perl -Tw
#
# This script performs janitorial tasks. It removes incomplete patch series,
# archives old jobs and purges older jobs and patches.
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
use WineTestBot::VMs;


$ENV{PATH} = "/usr/bin:/bin";
delete $ENV{ENV};

# Delete obsolete Jobs
if ($WineTestBot::Config::JobPurgeDays != 0)
{
  my $DeleteBefore = time() - $WineTestBot::Config::JobPurgeDays * 86400;
  my $Jobs = CreateJobs();
  foreach my $JobKey (@{$Jobs->GetKeys()})
  {
    my $Job = $Jobs->GetItem($JobKey);
    if (defined($Job->Ended) && $Job->Ended < $DeleteBefore)
    {
      LogMsg "Deleting job ", $Job->Id, "\n";
      system "rm", "-rf", "$DataDir/jobs/" . $Job->Id;
      my $ErrMessage = $Jobs->DeleteItem($Job);
      if (defined($ErrMessage))
      {
        LogMsg $ErrMessage, "\n";
      }
    }
  }
  $Jobs = undef;
}

# Delete PatchSets that are more than a day old
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
    LogMsg "Deleting pending series for ", $Set->EMail, "\n";
    $Sets->DeleteItem($Set);
    $MostRecentPatch->Disposition("Incomplete series, discarded");
    $MostRecentPatch->Save();
  }
}

# Delete obsolete Patches now that no Job references them
if ($WineTestBot::Config::JobPurgeDays != 0)
{
  $DeleteBefore = time() - $WineTestBot::Config::JobPurgeDays * 86400;
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
        LogMsg "Deleting patch ", $Patch->Id, "\n";
        unlink("$DataDir/patches/" . $Patch->Id);
        my $ErrMessage = $Patches->DeleteItem($Patch);
        if (defined($ErrMessage))
        {
          LogMsg $ErrMessage, "\n";
        }
      }
    }
  }
  $Patches = undef;
}

# Archive old Jobs, that is remove all their associated files
if ($WineTestBot::Config::JobArchiveDays != 0)
{
  my $ArchiveBefore = time() - $WineTestBot::Config::JobArchiveDays * 86400;
  my $Jobs = CreateJobs();
  $Jobs->FilterNotArchived();
  foreach my $JobKey (@{$Jobs->GetKeys()})
  {
    my $Job = $Jobs->GetItem($JobKey);
    if (defined($Job->Ended) && $Job->Ended < $ArchiveBefore)
    {
      LogMsg "Archiving job ", $Job->Id, "\n";

      my $Steps = $Job->Steps;
      foreach my $StepKey (@{$Steps->GetKeys()})
      {
        my $Step = $Steps->GetItem($StepKey);
        unlink "$DataDir/jobs/" . $Job->Id . "/" . $Step->No . "/" .
               $Step->FileName;
      }

      $Job->Archived(1);
      $Job->Save();
    }
  }
  $Jobs = undef;
}

# Purge deleted VMs if they are not referenced anymore
my $VMs = CreateVMs();
$VMs->AddFilter("Role", ["deleted"]);
my %DeleteList;
map { $DeleteList{$_} = 1 } @{$VMs->GetKeys()};

if (%DeleteList)
{
  my $Jobs = CreateJobs();
  foreach my $JobKey (@{$Jobs->GetKeys()})
  {
    my $Job = $Jobs->GetItem($JobKey);
    my $Steps = $Job->Steps;
    foreach my $StepKey (@{$Steps->GetKeys()})
    {
      my $Step = $Steps->GetItem($StepKey);
      my $Tasks = $Step->Tasks;
      foreach my $TaskKey (@{$Tasks->GetKeys()})
      {
        my $Task = $Tasks->GetItem($TaskKey);
        if (exists $DeleteList{$Task->VM->Name})
        {
          LogMsg "Keeping the ", $Task->VM->Name, " VM for task (", join(":", $JobKey, $StepKey, $TaskKey), ")\n";
          delete $DeleteList{$Task->VM->Name};
        }
      }
    }
  }
  foreach my $VMKey (keys %DeleteList)
  {
    my $VM = $VMs->GetItem($VMKey);
    my $ErrMessage = $VMs->DeleteItem($VM);
    if (!defined $ErrMessage)
    {
      LogMsg "Deleted the ", $VM->Name, " VM\n";
    }
  }
}
