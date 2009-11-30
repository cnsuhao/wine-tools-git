#!/usr/bin/perl -Tw

use strict;

use lib "/usr/lib/winetestbot/lib";
require "Config.pl";

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
  my ($BaseJob, $FileNameRandomPart) = @_;

  # First create a new job
  my $Jobs = WineTestBot::Jobs->CreateJobs();
  my $NewJob = $Jobs->Add();
  $NewJob->User(WineTestBot::Users->GetBatchUser());
  $NewJob->Priority($BaseJob ? 1 : 7);
  $NewJob->Remarks("http://test.winehq.org job - " .
                   ($BaseJob ? "base" : "other") . " VMs");

  # Add a step to the job
  my $Steps = $NewJob->Steps;
  my $NewStep = $Steps->Add();
  $NewStep->FileName("${FileNameRandomPart} winetest-latest.exe");
  $NewStep->InStaging(1);

  # Add a task for each VM
  my $Tasks = $NewStep->Tasks;
  my $VMs = CreateVMs();
  foreach my $VMKey (@{$VMs->SortKeysBySortOrder($VMs->GetKeys())})
  {
    my $VM = $VMs->GetItem($VMKey);
    if (($BaseJob && $VM->BaseOS) || (! $BaseJob && ! $VM->BaseOS))
    {
      my $Task = $Tasks->Add();
      $Task->VM($VM);
      $Task->Type("suite");
      $Task->Timeout($SuiteTimeout);
    }
  }

  # Now save the whole thing
  (my $ErrKey, my $ErrProperty, my $ErrMessage) = $Jobs->Save();
  if (defined($ErrMessage))
  {
    LogMsg "CheckForWinetestUpdate: Failed to save job: $ErrMessage\n";
    exit 1;
  }

  $NewStep->HandleStaging($NewJob->Id);
}

my $WINETEST_URL = "http://test.winehq.org/builds/winetest-latest.exe";

umask 002;
mkdir "$DataDir/latest";
mkdir "$DataDir/staging";

my $LatestFileName = "$DataDir/latest/winetest-latest.exe";
my $FileNameRandomPart = GenerateRandomString(32);
while (-e "$DataDir/staging/${FileNameRandomPart}_winetest-latest.exe")
{
  $FileNameRandomPart = GenerateRandomString(32);
}
my $StagingFileName = "$DataDir/staging/${FileNameRandomPart}_winetest-latest.exe";

my $UA = LWP::UserAgent->new();
$UA->agent("WineTestBot");
my $Request = HTTP::Request->new(GET => $WINETEST_URL);
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

AddJob(1, $FileNameRandomPart);

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
  AddJob(!1, $FileNameRandomPart);
}

FoundWinetestUpdate();

LogMsg "CheckForWinetestUpdate: submitted jobs\n";

exit;
