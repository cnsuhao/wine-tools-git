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
my $Name0 = $0;
$Name0 =~ s+^.*/++;

use WineTestBot::Config;
use WineTestBot::Jobs;
use WineTestBot::VMs;
use WineTestBot::Log;
use WineTestBot::Engine::Notify;


my $Debug;
sub Debug(@)
{
  print STDERR @_ if ($Debug);
}

sub Error(@)
{
  Debug("$Name0:error: ", @_);
  LogMsg @_;
}

sub LogTaskError($$)
{
  my ($ErrMessage, $FullErrFileName) = @_;
  Debug("$Name0:error: $ErrMessage");

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
    Error "Unable to open '$FullErrFileName' for writing: $!\n";
  }
}

sub FatalError($$$$$)
{
  my ($ErrMessage, $FullErrFileName, $Job, $Step, $Task) = @_;
  Debug("$Name0:error: $ErrMessage");

  my ($JobKey, $StepKey, $TaskKey) = @{$Task->GetMasterKey()};
  LogMsg "$JobKey/$StepKey/$TaskKey $ErrMessage";

  LogTaskError($ErrMessage, $FullErrFileName);
  if ($Step->Type eq "suite")
  {
    # Link the test suite's results for future use in WineSendLog.pl.
    my $LatestName = "$DataDir/latest/" . $Task->VM->Name . "_" .
                     ($Step->FileType eq "exe64" ? "64" : "32") . ".err";
    unlink($LatestName);
    link($FullErrFileName, $LatestName);
  }

  $Task->Status("boterror");
  $Task->Ended(time);
  $Task->Save();
  $Job->UpdateStatus();

  # Get the up-to-date VM status and update it if nobody else changed it
  my $VM = CreateVMs()->GetItem($Task->VM->GetKey());
  if ($VM->Status eq 'running')
  {
    $VM->Status('dirty');
    $VM->Save();
    RescheduleJobs();
  }

  exit 1;
}

sub TakeScreenshot($$)
{
  my ($VM, $FullScreenshotFileName) = @_;

  my ($ErrMessage, $ImageSize, $ImageBytes) = $VM->CaptureScreenImage();
  if (! defined($ErrMessage))
  {
    my $OldUMask = umask(002);
    if (open SCREENSHOT, ">$FullScreenshotFileName")
    {
      umask($OldUMask);
      print SCREENSHOT $ImageBytes;
      close SCREENSHOT;
    }
    else
    {
      umask($OldUMask);
      Error "Can't save screenshot: $!\n";
    }
  }
  else
  {
    Error "Can't capture screenshot: $ErrMessage\n";
  }
}

sub CountFailures($)
{
  my ($ReportFileName) = @_;

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

# Grab the command line options
my $Usage;
sub ValidateNumber($$)
{
  my ($Name, $Value) = @_;

  # Validate and untaint the value
  return $1 if ($Value =~ /^(\d+)$/);
  Error "$Value is not a valid $Name\n";
  $Usage = 2;
  return undef;
}

my ($JobId, $StepNo, $TaskNo);
while (@ARGV)
{
  my $Arg = shift @ARGV;
  if ($Arg eq "--debug")
  {
    $Debug = 1;
  }
  elsif ($Arg =~ /^(?:-\?|-h|--help)$/)
  {
    $Usage = 0;
    last;
  }
  elsif ($Arg =~ /^???/)
  {
    Error "unknown option '$Arg'\n";
    $Usage = 2;
    last;
  }
  elsif (!defined $JobId)
  {
    $JobId = ValidateNumber('job id', $Arg);
  }
  elsif (!defined $StepNo)
  {
    $StepNo = ValidateNumber('step number', $Arg);
  }
  elsif (!defined $TaskNo)
  {
    $TaskNo = ValidateNumber('task number', $Arg);
  }
  else
  {
    Error "unexpected argument '$Arg'\n";
    $Usage = 2;
    last;
  }
}

# Check parameters
if (!defined $Usage)
{
  if (!defined $JobId || !defined $StepNo || !defined $TaskNo)
  {
    Error "you must specify the job id, step number and task number\n";
    $Usage = 2;
  }
}
if (defined $Usage)
{
    print "Usage: $Name0 [--debug] [--help] JobId StepNo TaskNo\n";
    exit $Usage;
}

my $Job = CreateJobs()->GetItem($JobId);
if (!defined $Job)
{
  Error "Job $JobId does not exist\n";
  exit 1;
}
my $Step = $Job->Steps->GetItem($StepNo);
if (!defined $Step)
{
  Error "Step $StepNo of job $JobId does not exist\n";
  exit 1;
}
my $Task = $Step->Tasks->GetItem($TaskNo);
if (!defined $Task)
{
  Error "Step $StepNo task $TaskNo of job $JobId does not exist\n";
  exit 1;
}

my $OldUMask = umask(002);
mkdir "$DataDir/jobs/$JobId";
mkdir "$DataDir/jobs/$JobId/$StepNo";
mkdir "$DataDir/jobs/$JobId/$StepNo/$TaskNo";
umask($OldUMask);

my $VM = $Task->VM;
my $RptFileName = $VM->Name . ".rpt";
my $StepDir = "$DataDir/jobs/$JobId/$StepNo";
my $TaskDir = "$StepDir/$TaskNo";
my $FullLogFileName = "$TaskDir/log";
my $FullErrFileName = "$TaskDir/err";
my $FullScreenshotFileName = "$TaskDir/screenshot.png";

if (!$Debug and $VM->Status ne "running")
{
  FatalError "The VM is not ready for use (" . $VM->Status . ")\n",
             $FullErrFileName, $Job, $Step, $Task;
}
elsif ($Debug and !$VM->IsPoweredOn)
{
  FatalError "The VM is not powered on\n", $FullErrFileName, $Job, $Step, $Task;
}
LogMsg "Task $JobId/$StepNo/$TaskNo (" . $VM->Name . ") started\n";

my $Start = Time();
Debug("0.00 Setting the time\n");
my $TA = $VM->GetAgent();
if (!$TA->SetTime())
{
  # Not a fatal error
  LogTaskError("Unable to set the VM system time: ". $TA->GetLastError() ."\n", $FullErrFileName);
}

my $ErrMessage;
my $FileType = $Step->FileType;
if ($FileType ne "exe32" && $FileType ne "exe64")
{
  FatalError "Unexpected file type $FileType found\n",
             $FullErrFileName, $Job, $Step, $Task;
}
my $FileName = $Step->FileName;
Debug(Elapsed($Start), " Sending '$StepDir/$FileName'\n");
if (!$TA->SendFile("$StepDir/$FileName", $FileName, 0))
{
  $ErrMessage = $TA->GetLastError();
  FatalError "Can't copy exe to VM: $ErrMessage\n",
             $FullErrFileName, $Job, $Step, $Task;
}
my $TestLauncher = "TestLauncher" . 
                   ($FileType eq "exe64" ? "64" : "32") .
                   ".exe";
Debug(Elapsed($Start), " Sending '$BinDir/windows/$TestLauncher'\n");
if (!$TA->SendFile("$BinDir/windows/$TestLauncher", $TestLauncher, 0))
{
  $ErrMessage = $TA->GetLastError();
  FatalError "Can't copy TestLauncher to VM: $ErrMessage\n",
             $FullErrFileName, $Job, $Step, $Task;
}

my $Keepalive;
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
  $Keepalive = 20;
  my $CmdLineArg = $Task->CmdLineArg;
  if ($CmdLineArg)
  {
    $Script .= "$CmdLineArg ";
  }
  $Script .= "> $RptFileName\r\n";
}
elsif ($Step->Type eq "suite")
{
  $Keepalive = 60;
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
Debug(Elapsed($Start), " Sending the script: [$Script]\n");
if (!$TA->SendFileFromString($Script, "script.bat", $TestAgent::SENDFILE_EXE))
{
  $ErrMessage = $TA->GetLastError();
  FatalError "Can't send the script to VM: $ErrMessage\n",
             $FullErrFileName, $Job, $Step, $Task;
}

Debug(Elapsed($Start), " Running the script\n");
my $Pid = $TA->Run(["./script.bat"], 0);
if (!$Pid or !defined $TA->Wait($Pid, $Timeout, $Keepalive))
{
  $ErrMessage = "Failure running script in VM: " . $TA->GetLastError();
}

my $NewStatus = "boterror";
Debug(Elapsed($Start), " Retrieving the report file '$FullLogFileName'\n");
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

  chmod 0664, $FullLogFileName;
  if ($Step->Type eq "suite")
  {
    # Link the test suite's results for future use in WineSendLog.pl.
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

Debug(Elapsed($Start), " Taking a screenshot\n");
TakeScreenshot $VM, $FullScreenshotFileName;
if (defined $ErrMessage)
{
  FatalError "$ErrMessage\n", $FullErrFileName, $Job, $Step, $Task;
}
$TA->Disconnect();

Debug(Elapsed($Start), " Done. New task status: $NewStatus\n");
$Task->Status($NewStatus);
$Task->ChildPid(undef);
$Task->Ended(time);

$Task->Save();
$Job->UpdateStatus();

# Get the up-to-date VM status and update it if nobody else changed it
$VM = CreateVMs()->GetItem($VM->GetKey());
if ($VM->Status eq 'running')
{
  $VM->Status('dirty');
  $VM->Save();
  RescheduleJobs();
}

LogMsg "Task $JobId/$StepNo/$TaskNo (" . $VM->Name . ") completed\n";
exit 0;
