#!/usr/bin/perl -Tw
#
# Communicates with the build machine to have it perform the 'reconfig' task.
# See the bin/build/Reconfig.pl script.
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
my $StepDir = "$DataDir/jobs/$JobId/$StepNo";
my $TaskDir = "$StepDir/$TaskNo";
my $FullLogFileName = "$TaskDir/log";
my $FullErrFileName = "$TaskDir/err";

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

sub WrapUpAndExit($)
{
  my ($Status) = @_;

  # Update the Task and Job
  $Task->Status($Status);
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
    $VM->Status($Status eq 'queued' ? 'offline' :
                $Status eq 'completed' ? 'idle' : 'dirty');
    $VM->Save();
    RescheduleJobs();
  }

  my $Result = $VM->Name .": ". $VM->Status ." Task: $Status";
  LogMsg "Task $JobId/$StepNo/$TaskNo done ($Result)\n";
  Debug(Elapsed($Start), " Done. $Result\n");
  exit($Status eq 'completed' ? 0 : 1);}

sub FatalError($)
{
  my ($ErrMessage) = @_;

  LogMsg "$JobId/$StepNo/$TaskNo $ErrMessage";
  LogTaskError($ErrMessage);

  WrapUpAndExit('boterror');
}

sub FatalTAError($$)
{
  my ($TA, $ErrMessage) = @_;
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

  if ($IsPoweredOn)
  {
    $ErrMessage .= " The test VM has crashed, rebooted or lost connectivity (or the TestAgent server died)\n";
  }
  else
  {
    # Ignore the TestAgent error, it's irrelevant
    $ErrMessage = "The test VM is powered off!\n";
  }
  FatalError($ErrMessage);
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
# Run the build
#

my $Script = "#!/bin/sh\n" .
             "rm -f Reconfig.log\n" .
             "../bin/build/Reconfig.pl >>Reconfig.log 2>&1\n";
my $TA = $VM->GetAgent();
Debug(Elapsed($Start), " Sending the script: [$Script]\n");
if (!$TA->SendFileFromString($Script, "task", $TestAgent::SENDFILE_EXE))
{
  FatalTAError($TA, "Could not send the reconfig script to the VM");
}

Debug(Elapsed($Start), " Starting the script\n");
my $Pid = $TA->Run(["./task"], 0);
if (!$Pid)
{
  FatalTAError($TA, "Failed to start the build VM update");
}


#
# From that point on we want to at least try to grab the build
# log before giving up
#

my ($NewStatus, $ErrMessage, $TAError);
Debug(Elapsed($Start), " Waiting for the script (", $Task->Timeout, "s timeout)\n");
if (!defined $TA->Wait($Pid, $Task->Timeout, 60))
{
  $ErrMessage = $TA->GetLastError();
  if ($ErrMessage =~ /timed out waiting for the child process/)
  {
    $ErrMessage = "The build timed out\n";
    $NewStatus = "badbuild";
  }
  else
  {
    $TAError = "An error occurred while waiting for the build to complete: $ErrMessage";
    $ErrMessage = undef;
  }
}

Debug(Elapsed($Start), " Retrieving the reconfig log to '$FullLogFileName'\n");
if ($TA->GetFile("Reconfig.log", $FullLogFileName))
{
  if (open(my $LogFile, "<", $FullLogFileName))
  {
    # Collect and analyze the 'Reconfig:' status line(s).
    my $LogErrors;
    foreach my $Line (<$LogFile>)
    {
      chomp($Line);
      next if ($Line !~ /^Reconfig: (.*)$/);
      # Add the error message or an empty string for 'ok'
      $LogErrors = ($LogErrors || "") . ($1 ne "ok" ? "$1\n" : "");
    }
    close($LogFile);

    if (!defined $LogErrors)
    {
      if (!defined $ErrMessage)
      {
        $NewStatus = "badbuild";
        $ErrMessage = "Missing reconfig status line\n";
      }
      # otherwise $ErrMessage probably already explains why the reconfig
      # status line is missing
    }
    elsif ($LogErrors eq "")
    {
      # We must have gotten the full log and the build did succeed.
      # So forget any prior error.
      $NewStatus = "completed";
      $TAError = $ErrMessage = undef;
    }
    else
    {
      $NewStatus = "badbuild";
      $ErrMessage = $LogErrors . ($ErrMessage || "");
    }
  }
  else
  {
    FatalError("Unable to open the build log for reading: $!\n");
  }
}
elsif (!defined $TAError)
{
  $TAError = "An error occurred while retrieving the reconfig log: ". $TA->GetLastError();
}
$TA->Disconnect();

# Report the reconfig errors even though they may have been caused by
# TestAgent trouble.
LogTaskError($ErrMessage) if (defined $ErrMessage);
FatalTAError(undef, $TAError) if (defined $TAError);


#
# Update the build VM's snapshot
#

if ($NewStatus eq 'completed')
{
  Debug(Elapsed($Start), " Deleting the old ", $VM->IdleSnapshot, " snapshot\n");
  $ErrMessage = $VM->RemoveSnapshot($VM->IdleSnapshot);
  if (defined $ErrMessage)
  {
    # It's not clear if the snapshot is still usable. Rather than try to figure
    # it out now, let the next task deal with it.
    FatalError("Could not remove the ". $VM->IdleSnapshot ." snapshot: $ErrMessage\n");
  }

  Debug(Elapsed($Start), " Recreating the ", $VM->IdleSnapshot, " snapshot\n");
  $ErrMessage = $VM->CreateSnapshot($VM->IdleSnapshot);
  if (defined $ErrMessage)
  {
    # Without the snapshot the VM is not usable anymore but FatalError() will
    # just mark it as 'dirty'. It's only the next time it is used that the
    # problem will be noticed and that it will be taken offline.
    FatalError("Could not recreate the ". $VM->IdleSnapshot ." snapshot: $ErrMessage\n");
  }
}


#
# Wrap up
#

WrapUpAndExit($NewStatus);
