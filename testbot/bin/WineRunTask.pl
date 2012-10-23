#!/usr/bin/perl -Tw
#
# Sends and runs the tasks in the Windows test VMs.
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

use POSIX qw(:fcntl_h);
use WineTestBot::Config;
use WineTestBot::Jobs;
use WineTestBot::Log;
use WineTestBot::StepsTasks;
use WineTestBot::Engine::Notify;

sub FatalError
{
  my ($ErrMessage, $RptFileName, $Job, $Step, $Task) = @_;

  my $JobKey = defined($Job) ? $Job->GetKey() : "0";
  my $StepKey = defined($Step) ? $Step->GetKey() : "0";
  my $TaskKey = defined($Task) ? $Task->GetKey() : "0";

  LogMsg "WineRunTask: $JobKey/$StepKey/$TaskKey $ErrMessage";

  if ($Task)
  {
    $Task->Status("failed");
    $Task->Ended(time);
    $Task->Save();
    $Job->UpdateStatus();

    if ($Task->VM->Role ne "base")
    {
      $Task->VM->PowerOff();
    }
    $Task->VM->Status('dirty');
    $Task->VM->Save();
  }

  if ($RptFileName)
  {
    my $RPTFILE;
    my $OldUMask = umask(002);
    if (open RPTFILE, ">>$RptFileName")
    {
      print RPTFILE $ErrMessage;
      close RPTFILE;
    }
    umask($OldUMask);

    if ($Task && $Step->Type eq "suite")
    {
      my $LatestName = "$DataDir/latest/" . $Task->VM->Name . "_" .
                       ($Step->FileType eq "exe64" ? "64" : "32") . ".err";
      unlink($LatestName);
      link($RptFileName, $LatestName);
    }
  }

  TaskComplete($JobKey, $StepKey, $TaskKey);

  exit 1;
}

sub TakeScreenshot
{
  my ($VM, $FullScreenshotFileName) = @_;

  my ($ErrMessage, $ImageSize, $ImageBytes) = $VM->CaptureScreenImage();
  if (! defined($ErrMessage))
  {
    if (open SCREENSHOT, ">$FullScreenshotFileName")
    {
      print SCREENSHOT $ImageBytes;
      close SCREENSHOT;
    }
    else
    {
      LogMsg "WineRunTask: Can't save screenshot: $!\n";
    }
  }
  else
  {
    LogMsg "WineRunTask: Can't capture screenshot: $ErrMessage\n";
  }
}

sub CountFailures
{
  my $ReportFileName = $_[0];

  if (! open REPORTFILE, "<$ReportFileName")
  {
    return undef;
  }

  my $Failures;
  my $Line;
  while (defined($Line = <REPORTFILE>))
  {
    if ($Line =~ m/: \d+ tests? executed \(\d+ marked as todo, (\d+) failures?\), \d+ skipped\./)
    {
      $Failures += $1;
    }
    elsif ($Line =~ m/ done \(258\)/ ||
           $Line =~ m/: unhandled exception [0-9a-fA-F]{8} at /)
    {
      $Failures++;
    }
  }
  close REPORTFILE;

  return $Failures;
}

sub RetrieveLogFile
{
  my ($Job, $Step, $Task, $GuestLogFileName, $HostLogFileName) = @_;

  my $VM = $Task->VM;
  my $ErrMessage = $VM->CopyFileFromGuestToHost($GuestLogFileName,
                                                $HostLogFileName);
  chmod 0664, $HostLogFileName;
  if (defined($ErrMessage) || $Step->Type ne "suite")
  {
    return $ErrMessage;
  }

  my $LatestNameBase = "$DataDir/latest/" . $VM->Name . "_" .
                       ($Step->FileType eq "exe64" ? "64" : "32");
  unlink("${LatestNameBase}.log");
  unlink("${LatestNameBase}.err");
  link("$DataDir/jobs/" . $Job->Id . "/" . $Step->No . "/" . $Task->No . "/log",
       "${LatestNameBase}.log");

  return undef;
}

$ENV{PATH} = "/usr/bin:/bin";
delete $ENV{ENV};

my ($JobId, $StepNo, $TaskNo) = @ARGV;
if (! $JobId || ! $StepNo || ! $TaskNo)
{
  die "Usage: WineRunTask.pl JobId StepNo TaskNo";
}

# Untaint parameters
if ($JobId =~ /^(\d+)$/)
{
  $JobId = $1;
}
else
{
  FatalError "Invalid JobId $JobId\n";
}
if ($StepNo =~ /^(\d+)$/)
{
  $StepNo = $1;
}
else
{
  FatalError "Invalid StepNo $StepNo\n";
}
if ($TaskNo =~ /^(\d+)$/)
{
  $TaskNo = $1;
}
else
{
  FatalError "Invalid TaskNo $TaskNo\n";
}

my $Jobs = CreateJobs();
my $Job = $Jobs->GetItem($JobId);
if (! defined($Job))
{
  FatalError "Job $JobId doesn't exist\n";
}
my $Step = $Job->Steps->GetItem($StepNo);
if (! defined($Step))
{
  FatalError "Step $StepNo of job $JobId doesn't exist\n";
}
my $Task = $Step->Tasks->GetItem($TaskNo);
if (! defined($Task))
{
  FatalError "Step $StepNo task $TaskNo of job $JobId doesn't exist\n";
}

my $oldumask = umask(002);
mkdir "$DataDir/jobs/$JobId";
mkdir "$DataDir/jobs/$JobId/$StepNo";
mkdir "$DataDir/jobs/$JobId/$StepNo/$TaskNo";
umask($oldumask);

my $VM = $Task->VM;

LogMsg "WineRunTask: task $JobId/$StepNo/$TaskNo (" . $VM->Name . ") started\n";

my $RptFileName = $VM->Name . ".rpt";
my $StepDir = "$DataDir/jobs/$JobId/$StepNo";
my $TaskDir = "$StepDir/$TaskNo";
my $FullLogFileName = "$TaskDir/log";
my $FullErrFileName = "$TaskDir/err";
my $FullScreenshotFileName = "$TaskDir/screenshot.png";

sub TermHandler
{
  RetrieveLogFile $Job, $Step, $Task, "C:\\winetest\\$RptFileName",
                  $FullLogFileName;
  TakeScreenshot $VM, $FullScreenshotFileName;
  FatalError "Cancelled\n", $FullErrFileName, $Job, $Step, $Task;
}

$VM->Status('running');
$SIG{TERM} = \&TermHandler;
my ($ErrProperty, $ErrMessage) = $VM->Save();
if (defined($ErrMessage))
{
  FatalError "Can't set VM status to running: $ErrMessage\n",
             $FullErrFileName, $Job, $Step, $Task;
}

my $FileType = $Step->FileType;
if ($FileType ne "exe32" && $FileType ne "exe64")
{
  FatalError "Unexpected file type $FileType found\n",
             $FullErrFileName, $Job, $Step, $Task;
}
my $FileName = $Step->FileName;
$ErrMessage = $VM->CopyFileFromHostToGuest("$StepDir/$FileName",
                                           "C:\\winetest\\$FileName");
if (defined($ErrMessage))
{
  FatalError "Can't copy exe to VM: $ErrMessage\n",
             $FullErrFileName, $Job, $Step, $Task;
}
my $TestLauncher = "TestLauncher" . 
                   ($FileType eq "exe64" ? "64" : "32") .
                   ".exe";
$ErrMessage = $VM->CopyFileFromHostToGuest("$BinDir/windows/$TestLauncher",
                                           "C:\\winetest\\$TestLauncher");
if (defined($ErrMessage))
{
  FatalError "Can't copy TestLauncher to VM: $ErrMessage\n",
             $FullErrFileName, $Job, $Step, $Task;
}
$ErrMessage = $VM->CopyFileFromHostToGuest("$BinDir/windows/GenFixEnv.exe",
                                           "C:\\winetest\\GenFixEnv.exe");
if (defined($ErrMessage))
{
  FatalError "Can't copy GenFixEnv to VM: $ErrMessage\n",
             $FullErrFileName, $Job, $Step, $Task;
}
my $Script = "\@echo off\r\ncd \\winetest\r\nset WINETEST_DEBUG=" . $Step->DebugLevel .
             "\r\n";
if ($Step->ReportSuccessfulTests)
{
  $Script .= "set WINETEST_REPORT_SUCCESS=1\r\n";
}
$Script .= "GenFixEnv FixEnv.bat\r\ncall FixEnv.bat\r\ndel FixEnv.bat\r\n";
if ($Step->Type eq "single")
{
  $Script .= "$TestLauncher -t " . $Task->Timeout . " $FileName ";
  my $CmdLineArg = $Task->CmdLineArg;
  if ($CmdLineArg)
  {
    $Script .= "$CmdLineArg ";
  }
  $Script .= "> $RptFileName\r\n";
}
elsif ($Step->Type eq "suite")
{
  $Script .= "$FileName ";
  my $Tag = lc($TagPrefix) . "-" . lc($VM->Name);
  $Tag =~ s/[^a-zA-Z0-9]/-/g;
  if ($VM->Type eq "win64")
  {
    $Tag .= "-" . ($FileType eq "exe64" ? "64" : "32");
  }
  if (defined($WebHostName))
  {
    my $StepTask = 100 * $StepNo + $TaskNo;
    $Script .= '-u "http://' . $WebHostName . "/JobDetails.pl?Key=" .
               $JobId . "&scrshot_" . $StepTask . "=1#k" . $StepTask . '" ';
  }
  $Script .= "-q -o $RptFileName -t $Tag -m $AdminEMail\r\n" .
             "$FileName -q -s $RptFileName\r\n";
}

# Needed to exit the command prompt on Win9x/WinMe
$Script .= "cls\r\n";

$ErrMessage = $VM->RunScriptInGuestTimeout($Script, $Task->Timeout + 15);
my $LogErrMessage = RetrieveLogFile $Job, $Step, $Task,
                                    "C:\\winetest\\$RptFileName",
                                     $FullLogFileName;
TakeScreenshot $VM, $FullScreenshotFileName;
if (defined($ErrMessage))
{
  FatalError "Failure running script in VM: $ErrMessage\n",
             $FullErrFileName, $Job, $Step, $Task;
}
if (defined($LogErrMessage))
{
  FatalError "Can't copy log from VM: $LogErrMessage\n", $FullErrFileName,
             $Job, $Step, $Task;
}

$Task->Status("completed");
$Task->ChildPid(undef);
$Task->Ended(time);
my $TestFailures = CountFailures($FullLogFileName);
if (defined($TestFailures))
{
  $Task->TestFailures($TestFailures);
}
else
{
  my $OldUMask = umask(002);
  if (open ERRFILE, ">>$FullErrFileName")
  {
    print ERRFILE "No test summary line found\n";
    close ERRFILE;
  }
  umask($OldUMask);
}
$Task->Save();
$Job->UpdateStatus();
if ($Task->VM->Role ne "base")
{
  $Task->VM->PowerOff();
}
$VM->Status('dirty');
$VM->Save();

$Task = undef;
$Step = undef;
$Job = undef;
$Jobs = undef;

TaskComplete($JobId, $StepNo, $TaskNo);

LogMsg "WineRunTask: task $JobId/$StepNo/$TaskNo (" . $VM->Name . ") completed\n";

exit;
