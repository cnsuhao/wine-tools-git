#!/usr/bin/perl -Tw
#
# Checks if a new winetest binary is available on http://test.winehq.org/data/.
# If so, triggers an update of the build VM to the latest Wine source and
# runs the full test suite on the standard Windows test VMs.
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

use Fcntl;
use File::Compare;
use File::Copy;
use LWP::UserAgent;
use HTTP::Request;
use HTTP::Response;
use HTTP::Status;
use WineTestBot::Config;
use WineTestBot::Jobs;
use WineTestBot::Users;
use WineTestBot::Log;
use WineTestBot::Utils;
use WineTestBot::VMs;
use WineTestBot::Engine::Notify;

sub AddJob
{
  my ($BaseJob, $FileNameRandomPart, $Bits) = @_;

  # First create a new job
  my $Jobs = CreateJobs();
  my $NewJob = $Jobs->Add();
  $NewJob->User(GetBatchUser());
  $NewJob->Priority($BaseJob && $Bits == 32 ? 8 : 9);
  $NewJob->Remarks("WineTest: " .
                   ($Bits == 32 ? ($BaseJob ? "base" : "other") : "64-bit") .
                   " VMs");

  # Add a step to the job
  my $Steps = $NewJob->Steps;
  my $NewStep = $Steps->Add();
  my $BitsSuffix = ($Bits == 64 ? "64" : "");
  $NewStep->Type("suite");
  $NewStep->FileName("${FileNameRandomPart}_winetest${BitsSuffix}-latest.exe");
  $NewStep->FileType($Bits == 64 ? "exe64" : "exe32");
  $NewStep->InStaging(1);

  # Add a task for each VM
  my $Tasks = $NewStep->Tasks;
  my $HasTasks = !1;
  my $VMs = CreateVMs();
  if ($Bits == 64)
  {
      $VMs->AddFilter("Type", ["win64"]);
      $VMs->AddFilter("Role", ["base", "winetest"]);
  }
  elsif ($BaseJob)
  {
      $VMs->AddFilter("Type", ["win32", "win64"]);
      $VMs->AddFilter("Role", ["base"]);
  }
  else
  {
      $VMs->AddFilter("Type", ["win32", "win64"]);
      $VMs->AddFilter("Role", ["winetest"]);
  }
  foreach my $VMKey (@{$VMs->SortKeysBySortOrder($VMs->GetKeys())})
  {
    my $Task = $Tasks->Add();
    $Task->VM($VMs->GetItem($VMKey));
    $Task->Timeout($SuiteTimeout);
    $HasTasks = 1;
  }

  # Now save the whole thing
  if ($HasTasks)
  {
    (my $ErrKey, my $ErrProperty, my $ErrMessage) = $Jobs->Save();
    if (defined($ErrMessage))
    {
      LogMsg "Failed to save job: $ErrMessage\n";
      exit 1;
    }
  }
}

sub AddReconfigJob
{
  # First create a new job
  my $Jobs = CreateJobs();
  my $NewJob = $Jobs->Add();
  $NewJob->User(GetBatchUser());
  $NewJob->Priority(3);
  $NewJob->Remarks("Update Wine to latest git");

  # Add a step to the job
  my $Steps = $NewJob->Steps;
  my $NewStep = $Steps->Add();
  $NewStep->Type("reconfig");
  $NewStep->FileName("-");
  $NewStep->FileType("patchdlls");
  $NewStep->InStaging(!1);

  # Add a task for the build VM
  my $VMs = CreateVMs();
  $VMs->AddFilter("Type", ["build"]);
  $VMs->AddFilter("Role", ["base"]);
  my $BuildVM = ${$VMs->GetItems()}[0];
  my $Task = $NewStep->Tasks->Add();
  $Task->VM($BuildVM);
  $Task->Timeout($ReconfigTimeout);

  # Now save the whole thing
  my ($ErrKey, $ErrProperty, $ErrMessage) = $Jobs->Save();
  if (defined($ErrMessage))
  {
    LogMsg "Failed to save reconfig job: $ErrMessage\n";
    exit 1;
  }
}

my $WINETEST32_URL = "http://test.winehq.org/builds/winetest-latest.exe";
my $WINETEST64_URL = "http://test.winehq.org/builds/winetest64-latest.exe";

my $Bits = $ARGV[0];
if (! $Bits)
{
  die "Usage: CheckForWinetestUpdate.pl <bits>";
}

if ($Bits =~ m/^(32|64)$/)
{
  $Bits = $1;
}
else
{
  die "Invalid number of bits $Bits";
}

my $WinetestUrl = ($Bits == 64 ? $WINETEST64_URL : $WINETEST32_URL);
my $BitsSuffix = ($Bits == 64 ? "64" : "");

umask 002;
mkdir "$DataDir/latest";
mkdir "$DataDir/staging";

# Store the new WineTest executable in the staging directory:
# - So we can compare it to the reference one in the latest directory to
#   check that it is truly new.
# - Because we don't know the relevant Job and Step IDs yet and thus cannot
#   put it in the jobs directory tree.
my $FileNameRandomPart = GenerateRandomString(32);
while (-e "$DataDir/staging/${FileNameRandomPart}_winetest${BitsSuffix}-latest.exe")
{
  $FileNameRandomPart = GenerateRandomString(32);
}
my $StagingFileName = "$DataDir/staging/${FileNameRandomPart}_winetest${BitsSuffix}-latest.exe";

my $UA = LWP::UserAgent->new();
$UA->agent("WineTestBot");
my $Request = HTTP::Request->new(GET => $WinetestUrl);
my $LatestFileName = "$DataDir/latest/winetest${BitsSuffix}-latest.exe";
if (-r $LatestFileName)
{
  my $Since = gmtime((stat $LatestFileName)[9]);
  $Request->header("If-Modified-Since" => "$Since GMT");
}
my $Response = $UA->request($Request);
if ($Response->code != RC_OK)
{
  if ($Response->code != RC_NOT_MODIFIED)
  {
    LogMsg "Unexpected HTTP response code ", $Response->code, "\n";
    exit 1;
  }
  exit;
}

my $NewFile = 1;
if (! open STAGINGFILE, ">$StagingFileName")
{
  LogMsg "Can't create staging file $StagingFileName: $!\n";
  exit 1;
}
print STAGINGFILE $Response->decoded_content();
close STAGINGFILE;
if (-r $LatestFileName)
{
  $NewFile = compare($StagingFileName, $LatestFileName) != 0;
}
if (! $NewFile)
{
  unlink $StagingFileName;
  exit;
}
if (! copy($StagingFileName, $LatestFileName))
{
  LogMsg "Can't copy $StagingFileName to $LatestFileName: $!\n";
}
utime time, $Response->last_modified, $LatestFileName;

if ($Bits == 32)
{
  AddReconfigJob();
  AddJob(1, $FileNameRandomPart, $Bits);

  # Create another copy for the non-base VMs Job.
  $FileNameRandomPart = GenerateRandomString(32);
  while (-e "$DataDir/staging/${FileNameRandomPart}_winetest-latest.exe")
  {
    $FileNameRandomPart = GenerateRandomString(32);
  }
  $StagingFileName = "$DataDir/staging/${FileNameRandomPart}_winetest-latest.exe";
  if (!copy($LatestFileName, $StagingFileName))
  {
    LogMsg "Can't copy $LatestFileName to $StagingFileName: $!\n";
  }
  else
  {
    AddJob(!1, $FileNameRandomPart, $Bits);
  }
}
else
{
  AddJob(1, $FileNameRandomPart, $Bits);
}

RescheduleJobs();

LogMsg "Submitted jobs\n";

exit;
