#!/usr/bin/perl -Tw

use strict;

my $Dir;
sub BEGIN
{
  $0 =~ m=^(.*)/[^/]*$=;
  $Dir = $1;
}
use lib "$Dir/../lib";

use Fcntl;
use File::Compare;
use File::Copy;
use LWP::UserAgent;
use HTTP::Request;
use HTTP::Response;
use HTTP::Status;
use WineTestBot::Config;
use WineTestBot::Jobs;
use WineTestBot::Log;
use WineTestBot::Utils;
use WineTestBot::VMs;
use WineTestBot::Engine::Notify;

sub AddJob
{
  my ($BaseJob, $FileNameRandomPart, $Bits) = @_;

  # First create a new job
  my $Jobs = WineTestBot::Jobs->CreateJobs();
  my $NewJob = $Jobs->Add();
  $NewJob->User(WineTestBot::Users->GetBatchUser());
  $NewJob->Priority($BaseJob && $Bits == 32 ? 6 : 7);
  $NewJob->Remarks("http://test.winehq.org job - " .
                   ($Bits == 32 ? ($BaseJob ? "base" : "other") : "64-bit") .
                   " VMs");

  # Add a step to the job
  my $Steps = $NewJob->Steps;
  my $NewStep = $Steps->Add();
  my $BitsSuffix = ($Bits == 64 ? "64" : "");
  $NewStep->Type("suite");
  $NewStep->FileName("${FileNameRandomPart} winetest${BitsSuffix}-latest.exe");
  $NewStep->FileType($Bits == 64 ? "exe64" : "exe32");
  $NewStep->InStaging(1);

  # Add a task for each VM
  my $Tasks = $NewStep->Tasks;
  my $HasTasks = !1;
  my $VMs = CreateVMs();
  # Don't schedule the 'offline' ones
  $VMs->AddFilter("Status", ["reverting", "sleeping", "idle", "running", "dirty"]);
  foreach my $VMKey (@{$VMs->SortKeysBySortOrder($VMs->GetKeys())})
  {
    my $VM = $VMs->GetItem($VMKey);
    my $AddThisVM;
    if ($Bits == 32)
    {
      $AddThisVM = ($BaseJob && $VM->Type eq "base") ||
                   (! $BaseJob && $VM->Type eq "extra");
    }
    else
    {
      $AddThisVM = ($VM->Bits == 64 && $VM->Type ne "build");
    }
    if ($AddThisVM)
    {
      my $Task = $Tasks->Add();
      $Task->VM($VM);
      $Task->Timeout($SuiteTimeout);
      $HasTasks = 1;
    }
  }

  # Now save the whole thing
  if ($HasTasks)
  {
    (my $ErrKey, my $ErrProperty, my $ErrMessage) = $Jobs->Save();
    if (defined($ErrMessage))
    {
      LogMsg "CheckForWinetestUpdate: Failed to save job: $ErrMessage\n";
      exit 1;
    }

    $NewStep->HandleStaging($NewJob->Id);
  }
}

sub AddReconfigJob
{
  # First create a new job
  my $Jobs = WineTestBot::Jobs->CreateJobs();
  my $NewJob = $Jobs->Add();
  $NewJob->User(WineTestBot::Users->GetBatchUser());
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
  my $Tasks = $NewStep->Tasks;
  my $HasTasks = !1;
  my $VMs = CreateVMs();
  foreach my $VMKey (@{$VMs->SortKeysBySortOrder($VMs->GetKeys())})
  {
    my $VM = $VMs->GetItem($VMKey);
    if ($VM->Type eq "build")
    {
      my $Task = $Tasks->Add();
      $Task->VM($VM);
      $Task->Timeout($ReconfigTimeout);
      last;
    }
  }

  # Now save the whole thing
  (my $ErrKey, my $ErrProperty, my $ErrMessage) = $Jobs->Save();
  if (defined($ErrMessage))
  {
    LogMsg "CheckForWinetestUpdate: Failed to save reconfig job: $ErrMessage\n";
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

my $LatestFileName = "$DataDir/latest/winetest${BitsSuffix}-latest.exe";
my $FileNameRandomPart = GenerateRandomString(32);
while (-e "$DataDir/staging/${FileNameRandomPart}_winetest${BitsSuffix}-latest.exe")
{
  $FileNameRandomPart = GenerateRandomString(32);
}
my $StagingFileName = "$DataDir/staging/${FileNameRandomPart}_winetest${BitsSuffix}-latest.exe";

my $UA = LWP::UserAgent->new();
$UA->agent("WineTestBot");
my $Request = HTTP::Request->new(GET => $WinetestUrl);
my $NowDate = gmtime;
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
    LogMsg "CheckForWinetestUpdate: Unexpected HTTP response code ", 
           $Response->code, "\n";
    exit 1;
  }
  exit;
}

my $NewFile = 1;
if (! open STAGINGFILE, ">$StagingFileName")
{
  LogMsg "CheckForWinetestUpdate: can't create staging file $StagingFileName: $!\n";
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
  LogMsg "CheckForWinetestUpdate: Can't copy $StagingFileName to $LatestFileName: $!\n";
}
utime time, $Response->last_modified, $LatestFileName;

if ($Bits == 32)
{
  AddReconfigJob();
  AddJob(1, $FileNameRandomPart, $Bits);
  
  $FileNameRandomPart = GenerateRandomString(32);
  while (-e "$DataDir/staging/${FileNameRandomPart}_winetest-latest.exe")
  {
    $FileNameRandomPart = GenerateRandomString(32);
  }
  $StagingFileName = "$DataDir/staging/${FileNameRandomPart}_winetest-latest.exe";
  if (! copy($LatestFileName, $StagingFileName))
  {
    LogMsg "CheckForWinetestUpdate: Can't copy $LatestFileName to $StagingFileName: $!\n";
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

FoundWinetestUpdate($Bits);

LogMsg "CheckForWinetestUpdate: submitted jobs\n";

exit;
