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

use WineTestBot::Config;
use WineTestBot::Jobs;
use WineTestBot::Log;
use WineTestBot::Patches;
use WineTestBot::PendingPatchSets;
use WineTestBot::VMs;


$ENV{PATH} = "/usr/bin:/bin";
delete $ENV{ENV};

# Delete obsolete Jobs
if ($JobPurgeDays != 0)
{
  my $DeleteBefore = time() - $JobPurgeDays * 86400;
  my $Jobs = CreateJobs();
  foreach my $Job (@{$Jobs->GetItems()})
  {
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
my $Sets = CreatePendingPatchSets();
foreach my $Set (@{$Sets->GetItems()})
{
  my $MostRecentPatch;
  foreach my $Part (@{$Set->Parts->GetItems()})
  {
    my $Patch = $Part->Patch;
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
if ($JobPurgeDays != 0)
{
  $DeleteBefore = time() - $JobPurgeDays * 86400;
  my $Patches = CreatePatches();
  foreach my $Patch (@{$Patches->GetItems()})
  {
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
if ($JobArchiveDays != 0)
{
  my $ArchiveBefore = time() - $JobArchiveDays * 86400;
  my $Jobs = CreateJobs();
  $Jobs->FilterNotArchived();
  foreach my $Job (@{$Jobs->GetItems()})
  {
    if (defined($Job->Ended) && $Job->Ended < $ArchiveBefore)
    {
      LogMsg "Archiving job ", $Job->Id, "\n";
      foreach my $Step (@{$Job->Steps->GetItems()})
      {
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
  foreach my $Job (@{CreateJobs()->GetItems()})
  {
    foreach my $Step (@{$Job->Steps->GetItems()})
    {
      foreach my $Task (@{$Step->Tasks->GetItems()})
      {
        if (exists $DeleteList{$Task->VM->Name})
        {
          LogMsg "Keeping the ", $Task->VM->Name, " VM for task ", join("/", @{$Task->GetMasterKey()}), "\n";
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
