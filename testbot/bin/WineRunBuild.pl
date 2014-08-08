#!/usr/bin/perl -Tw
#
# Communicates with the build machine to have it perform the 'build' task.
# See the bin/build/Build.pl script.
#
# Copyright 2009 Ge van Geldorp
# Copyright 2013 Francois Gouget
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

sub FatalError($$$$)
{
  my ($ErrMessage, $FullErrFileName, $Job, $Task) = @_;
  Debug("$Name0:error: $ErrMessage");

  my ($JobKey, $StepKey, $TaskKey) = @{$Task->GetMasterKey()};
  LogMsg "$JobKey/$StepKey/$TaskKey $ErrMessage";

  LogTaskError($ErrMessage, $FullErrFileName);
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

sub ProcessLog($$)
{
  my ($FullLogFileName, $FullErrFileName) = @_;

  my ($Status, $Errors);
  if (open(my $LogFile, "<", $FullLogFileName))
  {
    # Collect and analyze the 'Build:' status line(s)
    $Errors = "";
    foreach my $Line (<$LogFile>)
    {
      chomp($Line);
      next if ($Line !~ /^Build: (.*)$/);
      if ($1 ne "ok")
      {
        $Errors .= "$1\n";
        $Status = ($1 eq "Patch failed to apply") ? "badpatch" : "badbuild";
      }
      elsif (!defined $Status)
      {
        $Status = "completed";
      }
    }
    close($LogFile);

    if (!defined $Status)
    {
      $Status = "boterror";
      $Errors = "Missing build status line\n";
    }
  }
  else
  {
    $Status = "boterror";
    $Errors = "Unable to open the log file\n";
    Error "Unable to open '$FullLogFileName' for reading: $!\n";
  }

  LogTaskError($Errors, $FullErrFileName) if ($Errors);
  return $Status;
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

my $StepDir = "$DataDir/jobs/$JobId/$StepNo";
my $TaskDir = "$StepDir/$TaskNo";
my $FullLogFileName = "$TaskDir/log";
my $FullErrFileName = "$TaskDir/err";

my $VM = $Task->VM;
if (!$Debug and $VM->Status ne "running")
{
  FatalError "The VM is not ready for use (" . $VM->Status . ")\n",
             $FullErrFileName, $Job, $Task;
}
elsif ($Debug and !$VM->IsPoweredOn)
{
  FatalError "The VM is not powered on\n", $FullErrFileName, $Job, $Task;
}
my $Start = Time();
LogMsg "Task $JobId/$StepNo/$TaskNo started\n";

my ($Run64, $BaseName);
foreach my $OtherStep (@{$Job->Steps->GetItems()})
{
  next if ($OtherStep->No == $StepNo);

  $Run64 = 1 if ($OtherStep->FileType eq "exe64");
  my $OtherFileName = $OtherStep->FileName;
  if ($OtherFileName =~ m/^([\w_.]+)_test(?:64)?\.exe$/)
  {
    my $OtherBaseName = $1;
    $OtherBaseName =~ s/\.exe$//;
    if (defined $BaseName and $BaseName ne $OtherBaseName)
    {
      FatalError "$OtherBaseName doesn't match previously found $BaseName\n",
                 $FullErrFileName, $Job, $Task;
    }
    $BaseName = $OtherBaseName;
  }
}
if (!defined $BaseName)
{
  FatalError "Can't determine base name\n", $FullErrFileName, $Job, $Task;
}

my $ErrMessage;
my $FileName = $Step->FileName;
my $TA = $VM->GetAgent();
Debug(Elapsed($Start), " Sending '$StepDir/$FileName'\n");
if (!$TA->SendFile("$StepDir/$FileName", "staging/patch.diff", 0))
{
  $ErrMessage = $TA->GetLastError();
  FatalError "Could not copy the patch to the VM: $ErrMessage\n",
             $FullErrFileName, $Job, $Task;
}
my $Script = "#!/bin/sh\n" .
             "rm -f Build.log\n" .
             "../bin/build/Build.pl patch.diff " . $Step->FileType .
             " $BaseName 32";
$Script .= ",64"if ($Run64);
$Script .= " >>Build.log 2>&1\n";
Debug(Elapsed($Start), " Sending the script: [$Script]\n");
if (!$TA->SendFileFromString($Script, "task", $TestAgent::SENDFILE_EXE))
{
  $ErrMessage = $TA->GetLastError();
  FatalError "Can't send the build script to the VM: $ErrMessage\n",
             $FullErrFileName, $Job, $Task;
}
Debug(Elapsed($Start), " Running the script\n");
my $Pid = $TA->Run(["./task"], 0);
if (!$Pid or !defined $TA->Wait($Pid, $Task->Timeout, 60))
{
  $ErrMessage = $TA->GetLastError();
  # Try to grab the build log before reporting the failure
}
my $NewStatus;
Debug(Elapsed($Start), " Retrieving the build log '$FullLogFileName'\n");
if ($TA->GetFile("Build.log", $FullLogFileName))
{
  $NewStatus = ProcessLog($FullLogFileName, $FullErrFileName);
}
elsif (!defined $ErrMessage)
{
  # This GetFile() error is the first one so report it
  $ErrMessage = $TA->GetLastError();
  FatalError "Can't copy the build log from the VM: $ErrMessage\n",
             $FullErrFileName, $Job, $Task;
}
if (defined $ErrMessage)
{
  # Now we can report the previous Run() / Wait() error
  if ($ErrMessage =~ /timed out waiting for the child process/)
  {
    $NewStatus = "badbuild";
    LogTaskError("The build timed out\n", $FullErrFileName);
  }
  else
  {
    FatalError "Failure running the build script in the VM: $ErrMessage\n",
               $FullErrFileName, $Job, $Task;
  }
}

# Don't try copying the test executables if the build step failed
if ($NewStatus eq "completed")
{
  foreach my $OtherStep (@{$Job->Steps->GetItems()})
  {
    next if ($OtherStep->No == $StepNo);

    my $OtherFileName = $OtherStep->FileName;
    next if ($OtherFileName !~ /^[\w_.]+_test(?:64)?\.exe$/);

    my $OtherStepDir = "$DataDir/jobs/$JobId/" . $OtherStep->No;
    mkdir $OtherStepDir;

    my $Bits = $OtherStep->FileType eq "exe64" ? "64" : "32";
    my $TestExecutable;
    if ($Step->FileType ne "patchprograms")
    {
      $TestExecutable = "build-mingw$Bits/dlls/$BaseName/tests/${BaseName}_test.exe";
    }
    else
    {
      $TestExecutable = "build-mingw$Bits/programs/$BaseName/tests/${BaseName}.exe_test.exe";
    }
    if (!$TA->GetFile($TestExecutable, "$OtherStepDir/$OtherFileName"))
    {
      $ErrMessage = $TA->GetLastError();
      FatalError "Can't copy the generated executable from the VM: $ErrMessage\n",
                 $FullErrFileName, $Job, $Task;
    }
    chmod 0664, "$OtherStepDir/$OtherFileName";
  }
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

LogMsg "Task $JobId/$StepNo/$TaskNo completed\n";
exit 0;
