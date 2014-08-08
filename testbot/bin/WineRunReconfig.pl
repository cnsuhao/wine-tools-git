#!/usr/bin/perl -Tw
#
# Communicates with the build machine to have it perform the 'reconfig' task.
# See the bin/build/Reconfig.pl script.
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
    # Collect and analyze the 'Reconfig:' status line(s)
    $Errors = "";
    foreach my $Line (<$LogFile>)
    {
      chomp($Line);
      next if ($Line !~ /^Reconfig: (.*)$/);
      if ($1 ne "ok")
      {
        $Errors .= "$1\n";
        $Status = "badbuild";
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
      $Errors = "Missing reconfig status line\n";
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

my $ErrMessage;
my $Script = "#!/bin/sh\n" .
             "rm -f Reconfig.log\n" .
             "../bin/build/Reconfig.pl >>Reconfig.log 2>&1\n";
my $TA = $VM->GetAgent();
Debug(Elapsed($Start), " Sending the script: [$Script]\n");
if (!$TA->SendFileFromString($Script, "task", $TestAgent::SENDFILE_EXE))
{
  $ErrMessage = $TA->GetLastError();
  FatalError "Can't send the script to the VM: $ErrMessage\n",
             $FullErrFileName, $Job, $Task;
}
Debug(Elapsed($Start), " Running the script\n");
my $Pid = $TA->Run(["./task"], 0);
if (!$Pid or !defined $TA->Wait($Pid, $Task->Timeout, 60))
{
  $ErrMessage = $TA->GetLastError();
  # Try to grab the reconfig log before reporting the failure
}
my $NewStatus;
Debug(Elapsed($Start), " Retrieving the reconfig log '$FullLogFileName'\n");
if ($TA->GetFile("Reconfig.log", $FullLogFileName))
{
  $NewStatus = ProcessLog($FullLogFileName, $FullErrFileName);
}
elsif (!defined $ErrMessage)
{
  # This GetFile() error is the first one so report it
  $ErrMessage = $TA->GetLastError();
  FatalError "Can't copy the reconfig log from the VM: $ErrMessage\n",
             $FullErrFileName, $Job, $Task;
}
if (defined $ErrMessage)
{
  # Now we can report the previous Run() / Wait() error
  if ($ErrMessage =~ /timed out waiting for the child process/)
  {
    $NewStatus = "badbuild";
    LogTaskError("The reconfig timed out\n", $FullErrFileName);
  }
  else
  {
    FatalError "Could not run the reconfig script in the VM: $ErrMessage\n",
               $FullErrFileName, $Job, $Task;
  }
}

$TA->Disconnect();

if ($NewStatus eq "completed")
{
  Debug(Elapsed($Start), " Deleting the old ", $VM->IdleSnapshot, " snapshot\n");
  $ErrMessage = $VM->RemoveSnapshot($VM->IdleSnapshot);
  if (defined($ErrMessage))
  {
    FatalError "Can't remove snapshot: $ErrMessage\n",
               $FullErrFileName, $Job, $Task;
  }

  Debug(Elapsed($Start), " Recreating the ", $VM->IdleSnapshot, " snapshot\n");
  $ErrMessage = $VM->CreateSnapshot($VM->IdleSnapshot);
  if (defined($ErrMessage))
  {
    # Without the snapshot the VM is not usable anymore but FatalError() will
    # just mark it as 'dirty'. It's only the next time it is used that the
    # problem will be noticed and that it will be taken offline.
    FatalError "Can't take snapshot: $ErrMessage\n",
               $FullErrFileName, $Job, $Task;
  }
}

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
  $VM->Status($NewStatus eq 'completed' ? 'idle' : 'dirty');
  $VM->Save();
  RescheduleJobs();
}

LogMsg "Task $JobId/$StepNo/$TaskNo completed\n";
exit 0;
