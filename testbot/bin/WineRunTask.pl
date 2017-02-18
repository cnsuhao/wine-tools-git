#!/usr/bin/perl -Tw
#
# Sends and runs the tasks in the Windows test VMs.
#
# Copyright 2009 Ge van Geldorp
# Copyright 2013-2016 Francois Gouget
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

sub TakeScreenshot($$)
{
  my ($VM, $FullScreenshotFileName) = @_;

  my ($ErrMessage, $ImageSize, $ImageBytes) = $VM->CaptureScreenImage();
  if (! defined($ErrMessage))
  {
    my $OldUMask = umask(002);
    if (open(my $Screenshot, ">", $FullScreenshotFileName))
    {
      print $Screenshot $ImageBytes;
      close($Screenshot);
    }
    else
    {
      Error "Could not open the screenshot file for writing: $!\n";
    }
    umask($OldUMask);
  }
  else
  {
    Error "Can't capture screenshot: $ErrMessage\n";
  }
}


#
# Setup and command line processing
#

$ENV{PATH} = "/usr/bin:/bin";
delete $ENV{ENV};

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
  elsif ($Arg =~ /^-/)
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

my $Start = Time();
LogMsg "Task $JobId/$StepNo/$TaskNo started\n";


#
# Error handling helpers
#

sub LogTaskError($)
{
  my ($ErrMessage) = @_;
  Debug("$Name0:error: ", $ErrMessage);

  my $OldUMask = umask(002);
  if (open(my $ErrFile, ">>", $FullErrFileName))
  {
    print $ErrFile $ErrMessage;
    close($ErrFile);
  }
  else
  {
    Error "Unable to open '$FullErrFileName' for writing: $!\n";
  }
  umask($OldUMask);
}

sub WrapUpAndExit($;$)
{
  my ($Status, $TestFailures) = @_;

  # Update the Task and Job
  $Task->Status($Status);
  $Task->TestFailures($TestFailures);
  $Task->ChildPid(undef);
  if ($Status eq 'queued')
  {
    $Task->Started(undef);
    $Task->Ended(undef);
    # Leave the Task files around so they can be seen until the next run
  }
  else
  {
    $Task->Ended(time());
  }
  $Task->Save();
  $Job->UpdateStatus();

  # Get the up-to-date VM status and update it if nobody else changed it
  $VM = CreateVMs()->GetItem($VM->GetKey());
  if ($VM->Status eq 'running')
  {
    $VM->Status($Status eq 'queued' ? 'offline' : 'dirty');
    $VM->Save();
    RescheduleJobs();
  }

  if ($Status eq 'completed' and $Step->Type eq 'suite')
  {
    # Update the reference VM suite results for WineSendLog.pl
    my $LatestBaseName = join("", "$DataDir/latest/", $Task->VM->Name, "_",
                              $Step->FileType eq "exe64" ? "64" : "32");
    unlink("$LatestBaseName.log");
    link($FullLogFileName, "$LatestBaseName.log") if (-f $FullLogFileName);
    unlink("$LatestBaseName.err");
    link($FullErrFileName, "$LatestBaseName.err") if (-f $FullErrFileName);
  }

  my $Result = $VM->Name .": ". $VM->Status ." Task: $Status Failures: ". (defined $TestFailures ? $TestFailures : "unset");
  LogMsg "Task $JobId/$StepNo/$TaskNo done ($Result)\n";
  Debug(Elapsed($Start), " Done. $Result\n");
  exit($Status eq 'completed' ? 0 : 1);
}

sub FatalError($)
{
  my ($ErrMessage) = @_;

  LogMsg "$JobId/$StepNo/$TaskNo $ErrMessage";
  LogTaskError($ErrMessage);

  WrapUpAndExit('boterror');
}

sub FatalTAError($$;$)
{
  my ($TA, $ErrMessage, $PossibleCrash) = @_;
  $ErrMessage .= ": ". $TA->GetLastError() if (defined $TA);

  # A TestAgent operation failed, see if the VM is still accessible
  my $IsPoweredOn = $VM->IsPoweredOn();
  if (!defined $IsPoweredOn)
  {
    # The VM host is not accessible anymore so mark the VM as offline and
    # requeue the task.
    Error("$ErrMessage\n");
    WrapUpAndExit('queued');
  }

  my $VMState;
  if ($IsPoweredOn)
  {
    $VMState = "The test VM has crashed, rebooted or lost connectivity (or the TestAgent server died)\n";
  }
  else
  {
    $VMState = "The test VM is powered off! Did the test shut it down?\n";
    # Ignore the TestAgent error, it's irrelevant
    $ErrMessage = "";
  }
  if ($PossibleCrash)
  {
    # The test did it!
    $ErrMessage .= "\n" if ($ErrMessage);
    LogTaskError("$ErrMessage$VMState");
    WrapUpAndExit('completed', 1);
  }
  $ErrMessage .= " " if ($ErrMessage);
  FatalError("$ErrMessage$VMState");
}


#
# Check the VM
#

if (!$Debug and $VM->Status ne "running")
{
  FatalError("The VM is not ready for use (" . $VM->Status . ")\n");
}
elsif ($Debug and !$VM->IsPoweredOn)
{
  FatalError("The VM is not powered on\n");
}


#
# Setup the VM
#

my $TA = $VM->GetAgent();
Debug(Elapsed($Start), " Setting the time\n");
if (!$TA->SetTime())
{
  # Not a fatal error
  LogTaskError("Unable to set the VM system time: ". $TA->GetLastError() .". Maybe the TestAgentd process is missing the required privileges.\n");
}

my $FileType = $Step->FileType;
if ($FileType ne "exe32" && $FileType ne "exe64")
{
  FatalError("Unexpected file type $FileType found\n");
}
my $FileName = $Step->FileName;
Debug(Elapsed($Start), " Sending '$StepDir/$FileName'\n");
if (!$TA->SendFile("$StepDir/$FileName", $FileName, 0))
{
  FatalTAError($TA, "Could not copy the test executable to the VM");
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
  my $TestLauncher = "TestLauncher" . ($FileType eq "exe64" ? "64" : "32") . ".exe";
  Debug(Elapsed($Start), " Sending '$BinDir/windows/$TestLauncher'\n");
  if (!$TA->SendFile("$BinDir/windows/$TestLauncher", $TestLauncher, 0))
  {
    FatalTAError($TA, "Could not copy TestLauncher to the VM");
  }

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
  FatalTAError($TA, "Could not send the script to the VM");
}


#
# Run the test
#

Debug(Elapsed($Start), " Starting the script\n");
my $Pid = $TA->Run(["./script.bat"], 0);
if (!$Pid)
{
  FatalTAError($TA, "Failed to start the test");
}


#
# From that point on we want to at least try to grab the test
# log and a screenshot before giving up
#

my $NewStatus = 'completed';
my ($TestFailures, $TAError, $PossibleCrash);
Debug(Elapsed($Start), " Waiting for the script (", $Task->Timeout, "s timeout)\n");
if (!defined $TA->Wait($Pid, $Timeout, $Keepalive))
{
  my $ErrMessage = $TA->GetLastError();
  if ($ErrMessage =~ /timed out waiting for the child process/)
  {
    LogTaskError("The test timed out\n");
    $TestFailures = 1;
  }
  else
  {
    $PossibleCrash = 1;
    $TAError = "An error occurred while waiting for the test to complete: $ErrMessage";
  }
}

Debug(Elapsed($Start), " Retrieving the report file to '$FullLogFileName'\n");
if ($TA->GetFile($RptFileName, $FullLogFileName))
{
  chmod 0664, $FullLogFileName;
  if (open(my $LogFile, "<", $FullLogFileName))
  {
    # Note that for the TestBot we don't really care about the todos and skips
    my ($CurrentDll, $CurrentUnit, $LineFailures, $SummaryFailures) = ("", "", 0, 0);
    my ($CurrentIsPolluted, %CurrentPids, $LogFailures);
    foreach my $Line (<$LogFile>)
    {
      # There may be more than one summary line due to child processes
      if ($Line =~ m%([_.a-z0-9]+):([_a-z0-9]+) start (?:-|[/_.a-z0-9]+) (?:-|[.0-9a-f]+)\r?$%)
      {
        my ($Dll, $Unit) = ($1, $2);
        if ($CurrentDll ne "")
        {
          LogTaskError("The done line is missing for $CurrentDll:$CurrentUnit\n");
          $LogFailures++;
        }
        ($CurrentDll, $CurrentUnit) = ($Dll, $Unit);
      }
      elsif ($Line =~ /^([_a-z0-9]+)\.c:\d+: Test failed: / or
             ($CurrentUnit ne "" and
              $Line =~ /($CurrentUnit)\.c:\d+: Test failed: /))
      {
        # If the failure is not for the current test unit we'll let its
        # developer hash it out with the polluter ;-)
        $CurrentIsPolluted = 1 if ($1 ne $CurrentUnit);
        $LineFailures++;
      }
      elsif ($Line =~ /^(?:([0-9a-f]+):)?([_.a-z0-9]+): unhandled exception [0-9a-fA-F]{8} at / or
             ($CurrentUnit ne "" and
              $Line =~ /(?:([0-9a-f]+):)?($CurrentUnit): unhandled exception [0-9a-fA-F]{8} at /))
      {
        my ($Pid, $Unit) = ($1, $2);

        if ($Unit eq $CurrentUnit)
        {
          # This also replaces a test summary line.
          $CurrentPids{$Pid || 0} = 1;
          $SummaryFailures++;
        }
        else
        {
          $CurrentIsPolluted = 1;
        }
        $LineFailures++;
      }
      elsif ($Line =~ /^(?:([0-9a-f]+):)?([_a-z0-9]+): \d+ tests? executed \((\d+) marked as todo, (\d+) failures?\), \d+ skipped\./ or
             ($CurrentUnit ne "" and
              $Line =~ /(?:([0-9a-f]+):)?($CurrentUnit): \d+ tests? executed \((\d+) marked as todo, (\d+) failures?\), \d+ skipped\./))
      {
        my ($Pid, $Unit, $Todo, $Failures) = ($1, $2, $3, $4);

        if ($Unit eq $CurrentUnit)
        {
          $CurrentPids{$Pid || 0} = 1;
          $SummaryFailures += $Failures;
        }
        else
        {
          $CurrentIsPolluted = 1;
          if ($Todo or $Failures)
          {
            LogTaskError("Found a misplaced '$Unit' test summary line.\n");
            $LogFailures++;
          }
        }
      }
      elsif ($Line =~ /^([_.a-z0-9]+):([_a-z0-9]+)(?::([0-9a-f]+))? done \((-?\d+)\)(?:\r?$| in)/)
      {
        my ($Dll, $Unit, $Pid, $Rc) = ($1, $2, $3, $4);

        if ($Dll ne $CurrentDll or $Unit ne $CurrentUnit)
        {
          LogTaskError("The start line is missing for $Dll:$Unit\n");
          $LogFailures++;
          $CurrentIsPolluted = 1;
        }

        # Verify the summary lines
        if (!$CurrentIsPolluted)
        {
          if ($LineFailures != 0 and $SummaryFailures == 0)
          {
            LogTaskError("$Dll:$Unit has unreported failures\n");
            $LogFailures++;
          }
          elsif ($LineFailures == 0 and $SummaryFailures != 0)
          {
            LogTaskError("Some test failed messages are missing for $Dll:$Unit\n");
            $LogFailures++;
          }
        }
        # Note that $SummaryFailures may count some failures twice so only use
        # it as a fallback for $LineFailures.
        $LineFailures ||= $SummaryFailures;

        if (!$CurrentIsPolluted)
        {
          # Verify the exit code
          if ($LineFailures != 0 and $Rc == 0)
          {
            LogTaskError("$Dll:$Unit returned success despite having failures\n");
            $LogFailures++;
          }
          elsif ($Rc == 258)
          {
            # This is a timeout
            $LogFailures++;
          }
          elsif ($LineFailures == 0 and $Rc != 0)
          {
            LogTaskError("$Dll:$Unit returned an error ($Rc) despite having no failures\n");
            $LogFailures++;
          }
        }

        if ($Rc != 258 and
            ((!$Pid and !%CurrentPids) or
             ($Pid and !$CurrentPids{$Pid} and !$CurrentPids{0})))
        {
          LogTaskError("$Dll:$Unit has no test summary line (early exit of the main process?)\n");
          $LogFailures++;
        }

        $LogFailures += $LineFailures;

        $CurrentDll = $CurrentUnit = "";
        %CurrentPids = ();
        $CurrentIsPolluted = $LineFailures = $SummaryFailures = 0;
      }
    }
    close($LogFile);

    if ($TimedOut)
    {
      # The report got truncated due to the timeout so ignore the other checks
    }
    elsif (!defined $LogFailures)
    {
      LogTaskError("Found no trace of a test summary line or of a crash\n");
      $LogFailures = 1;
    }
    elsif ($CurrentDll ne "")
    {
      LogTaskError("The report seems to have been truncated\n");
      $LogFailures++;
    }
    elsif ($LineFailures or $SummaryFailures)
    {
      LogTaskError("Found a trailing test summary or test failed line.\n");
      $LogFailures++;
    }
    # $LogFailures can legitimately be undefined in case of a timeout
    $TestFailures += $LogFailures || 0;
  }
  else
  {
    $NewStatus = 'boterror';
    Error "Unable to open '$FullLogFileName' for reading: $!\n";
    LogTaskError("Unable to open the log file for reading: $!\n");
  }
}
elsif (!defined $TAError)
{
  $TAError = "An error occurred while retrieving the test report: ". $TA->GetLastError();
}
$TA->Disconnect();


Debug(Elapsed($Start), " Taking a screenshot\n");
TakeScreenshot($VM, $FullScreenshotFileName);

FatalTAError(undef, $TAError, $PossibleCrash) if (defined $TAError);


#
# Wrap up
#

WrapUpAndExit($NewStatus, $TestFailures);
