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

use POSIX qw(:fcntl_h);
use WineTestBot::Config;
use WineTestBot::Jobs;
use WineTestBot::Log;
use WineTestBot::Engine::Notify;

sub LogTaskError($$)
{
  my ($ErrMessage, $FullErrFileName) = @_;
  my $OldUMask = umask(002);
  if (open(my $ErrFile, ">>", $FullErrFileName))
  {
    umask($OldUMask);
    print $ErrFile $ErrMessage;
    close($ErrFile);
  }
  else
  {
    umask($OldUMask);
    LogMsg "Unable to open '$FullErrFileName' for writing: $!\n";
  }
}

sub FatalError($$$$$)
{
  my ($ErrMessage, $FullErrFileName, $Job, $Step, $Task) = @_;

  my ($JobKey, $StepKey, $TaskKey) = @{$Task->GetMasterKey()};
  LogMsg "$JobKey/$StepKey/$TaskKey $ErrMessage";

  LogTaskError($ErrMessage, $FullErrFileName);
  if ($Step->Type eq "suite")
  {
    my $LatestName = "$DataDir/latest/" . $Task->VM->Name . "_" .
                     ($Step->FileType eq "exe64" ? "64" : "32") . ".err";
    unlink($LatestName);
    link($FullErrFileName, $LatestName);
  }

  $Task->Status("boterror");
  $Task->Ended(time);
  $Task->Save();
  $Job->UpdateStatus();

  my $VM = $Task->VM;
  $VM->PowerOff() if ($VM->Role ne "base");
  $VM->Status('dirty');
  $VM->Save();

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
      LogMsg "Can't save screenshot: $!\n";
    }
  }
  else
  {
    LogMsg "Can't capture screenshot: $ErrMessage\n";
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
  LogMsg "Invalid JobId $JobId\n";
  exit 1;
}
if ($StepNo =~ /^(\d+)$/)
{
  $StepNo = $1;
}
else
{
  LogMsg "Invalid StepNo $StepNo\n";
  exit 1;
}
if ($TaskNo =~ /^(\d+)$/)
{
  $TaskNo = $1;
}
else
{
  LogMsg "Invalid TaskNo $TaskNo\n";
  exit 1;
}

my $Job = CreateJobs()->GetItem($JobId);
if (!defined $Job)
{
  LogMsg "Job $JobId doesn't exist\n";
  exit 1;
}
my $Step = $Job->Steps->GetItem($StepNo);
if (!defined $Step)
{
  LogMsg "Step $StepNo of job $JobId doesn't exist\n";
  exit 1;
}
my $Task = $Step->Tasks->GetItem($TaskNo);
if (!defined $Task)
{
  LogMsg "Step $StepNo task $TaskNo of job $JobId doesn't exist\n";
  exit 1;
}

my $oldumask = umask(002);
mkdir "$DataDir/jobs/$JobId";
mkdir "$DataDir/jobs/$JobId/$StepNo";
mkdir "$DataDir/jobs/$JobId/$StepNo/$TaskNo";
umask($oldumask);

my $VM = $Task->VM;
my $TA = $VM->GetAgent();

LogMsg "Task $JobId/$StepNo/$TaskNo (" . $VM->Name . ") started\n";

my $RptFileName = $VM->Name . ".rpt";
my $StepDir = "$DataDir/jobs/$JobId/$StepNo";
my $TaskDir = "$StepDir/$TaskNo";
my $FullLogFileName = "$TaskDir/log";
my $FullErrFileName = "$TaskDir/err";
my $FullScreenshotFileName = "$TaskDir/screenshot.png";

# Normally the Engine has already set the VM status to 'running'.
# Do it anyway in case we're called manually from the command line.
if ($VM->Status ne "idle" and $VM->Status ne "running")
{
  FatalError "The VM is not ready for use (" . $VM->Status . ")\n",
             $FullErrFileName, $Job, $Step, $Task;
}
$VM->Status('running');
my ($ErrProperty, $ErrMessage) = $VM->Save();
if (defined $ErrMessage)
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
if (!$TA->SendFile("$StepDir/$FileName", $FileName, 0))
{
  $ErrMessage = $TA->GetLastError();
  FatalError "Can't copy exe to VM: $ErrMessage\n",
             $FullErrFileName, $Job, $Step, $Task;
}
my $TestLauncher = "TestLauncher" . 
                   ($FileType eq "exe64" ? "64" : "32") .
                   ".exe";
if (!$TA->SendFile("$BinDir/windows/$TestLauncher", $TestLauncher, 0))
{
  $ErrMessage = $TA->GetLastError();
  FatalError "Can't copy TestLauncher to VM: $ErrMessage\n",
             $FullErrFileName, $Job, $Step, $Task;
}

my $Timeout = $Task->Timeout;
my $Script = "\@echo off\r\nset WINETEST_DEBUG=" . $Step->DebugLevel .
             "\r\n";
if ($Step->ReportSuccessfulTests)
{
  $Script .= "set WINETEST_REPORT_SUCCESS=1\r\n";
}
if ($Step->Type eq "single")
{
  $Script .= "$TestLauncher -t $Timeout $FileName ";
  # Add 1 second to the timeout so the client-side Wait() does not time out
  # right before $TestLauncher does.
  $Timeout += 1;
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
  my $Info = $VM->Description ? $VM->Description : "";
  if ($VM->Details)
  {
      $Info .= ": " if ($Info ne "");
      $Info .=  $VM->Details;
  }
  # Escape the arguments for cmd's command interpreter
  my $EMail = $AdminEMail;
  $EMail =~ s/"/\\"/g;
  $EMail =~ s/%/%%/g;
  $EMail =~ s/%/%%/g;
  $Info =~ s/"/\\"/g;
  $Info =~ s/%/%%/g;
  $Info =~ s/%/%%/g;
  $Script .= "-q -o $RptFileName -t $Tag -m \"$EMail\" -i \"$Info\"\r\n" .
             "$FileName -q -s $RptFileName\r\n";
}
if (!$TA->SendFileFromString($Script, "script.bat", $TestAgent::SENDFILE_EXE))
{
  $ErrMessage = $TA->GetLastError();
  FatalError "Can't send the script to VM: $ErrMessage\n",
             $FullErrFileName, $Job, $Step, $Task;
}

my $Pid = $TA->Run(["./script.bat"], 0);
if (!$Pid or !defined $TA->Wait($Pid, $Timeout))
{
  $ErrMessage = "Failure running script in VM: " . $TA->GetLastError();
}

my $NewStatus = "boterror";
if ($TA->GetFile($RptFileName, $FullLogFileName))
{
  my $TestFailures = CountFailures($FullLogFileName);
  if (!defined $TestFailures)
  {
    if (($ErrMessage || "") =~ /timed out waiting for the child process/)
    {
      LogTaskError("The test timed out\n", $FullErrFileName);
      $ErrMessage = undef;
    }
    else
    {
      LogTaskError("No test summary line found\n", $FullErrFileName);
    }
    $TestFailures = 1;
  }
  $Task->TestFailures($TestFailures);
  $NewStatus = "completed";

  if ($Step->Type eq "suite")
  {
    chmod 0664, $FullLogFileName;
  }
  else
  {
    chmod 0664, $FullLogFileName;
    my $LatestNameBase = "$DataDir/latest/" . $VM->Name . "_" .
                         ($Step->FileType eq "exe64" ? "64" : "32");
    unlink("${LatestNameBase}.log");
    unlink("${LatestNameBase}.err");
    link("$DataDir/jobs/" . $Job->Id . "/" . $Step->No . "/" . $Task->No . "/log",
         "${LatestNameBase}.log");
  }
}
elsif (!defined $ErrMessage)
{
  $ErrMessage = "Can't copy log from VM: " . $TA->GetLastError();
}

TakeScreenshot $VM, $FullScreenshotFileName;
if (defined $ErrMessage)
{
  FatalError "$ErrMessage\n", $FullErrFileName, $Job, $Step, $Task;
}
$TA->Disconnect();

$Task->Status($NewStatus);
$Task->ChildPid(undef);
$Task->Ended(time);

$Task->Save();
$Job->UpdateStatus();

$VM->PowerOff() if ($VM->Role ne "base");
$VM->Status('dirty');
$VM->Save();

$Task = undef;
$Step = undef;
$Job = undef;

TaskComplete($JobId, $StepNo, $TaskNo);

LogMsg "Task $JobId/$StepNo/$TaskNo (" . $VM->Name . ") completed\n";
exit 0;
