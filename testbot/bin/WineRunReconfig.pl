#!/usr/bin/perl -Tw
#
# Communicates with the build machine to have it perform the 'reconfig' task.
# See the bin/build/Reconfig.pl script.
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

use WineTestBot::Config;
use WineTestBot::Jobs;
use WineTestBot::Log;
use WineTestBot::Engine::Notify;

sub FatalError
{
  my ($ErrMessage, $RptFileName, $Job, $Step, $Task) = @_;

  my $JobKey = defined($Job) ? $Job->GetKey() : "0";
  my $StepKey = defined($Step) ? $Step->GetKey() : "0";
  my $TaskKey = defined($Task) ? $Task->GetKey() : "0";

  LogMsg "$JobKey/$StepKey/$TaskKey $ErrMessage";
  if ($RptFileName)
  {
    my $RPTFILE;
    if (open RPTFILE, ">>$RptFileName")
    {
      print RPTFILE $ErrMessage;
      close RPTFILE;
    }
  }

  if ($Task)
  {
    $Task->Status("failed");
    $Task->Ended(time);
    $Task->Save();
    $Job->UpdateStatus();

    $Task->VM->Status('dirty');
    $Task->VM->Save();

    TaskComplete($JobKey, $StepKey, $TaskKey);
  }

  exit 1;
}

sub ProcessRawlog
{
  my ($FullRawlogFileName, $FullLogFileName, $FullErrFileName) = @_;

  my $FoundOk = !1;
  if (open RAWLOG, "<$FullRawlogFileName")
  {
    if (open LOG, ">$FullLogFileName")
    {
      if (open ERR, ">$FullErrFileName")
      {
        my $Line;
        while (defined($Line = <RAWLOG>))
        {
          chomp($Line);
          if ($Line =~ m/^Reconfig: (.*)$/)
          {
            if ($1 eq "ok")
            {
              $FoundOk = 1;
            }
            else
            {
              print ERR "$1\n";
            }
          }
          else
          {
            print LOG "$Line\n";
          }
        }

        close ERR;
        if (-z $FullErrFileName)
        {
          unlink($FullErrFileName);
        }
      }

      close LOG;
    }

    close RAWLOG;
    unlink($FullRawlogFileName);
  }

  return $FoundOk;
}

$ENV{PATH} = "/usr/bin:/bin";
delete $ENV{ENV};

my ($JobId, $StepNo, $TaskNo) = @ARGV;
if (! $JobId || ! $StepNo || ! $TaskNo)
{
  die "Usage: WineRunReconfig.pl JobId StepNo TaskNo";
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

my $Job = CreateJobs()->GetItem($JobId);
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

umask(002);
mkdir "$DataDir/jobs/$JobId";
mkdir "$DataDir/jobs/$JobId/$StepNo";
mkdir "$DataDir/jobs/$JobId/$StepNo/$TaskNo";

my $VM = $Task->VM;
my $TA = $VM->GetAgent();

LogMsg "Task $JobId/$StepNo/$TaskNo started\n";

my $StepDir = "$DataDir/jobs/$JobId/$StepNo";
my $TaskDir = "$StepDir/$TaskNo";
my $FullRawlogFileName = "$TaskDir/rawlog";
my $FullLogFileName = "$TaskDir/log";
my $FullErrFileName = "$TaskDir/err";

$VM->Status('running');
my ($ErrProperty, $ErrMessage) = $VM->Save();
if (defined($ErrMessage))
{
  FatalError "Can't set VM status to running: $ErrMessage\n",
             $FullErrFileName, $Job, $Step, $Task;
}
my $Script = "#!/bin/sh\n" .
             "rm -f Reconfig.log\n" .
             "../bin/build/Reconfig.pl >>Reconfig.log 2>&1\n";
if (!$TA->SendFileFromString($Script, "task", $TestAgent::SENDFILE_EXE))
{
  $ErrMessage = $TA->GetLastError();
  FatalError "Can't send the script to VM: $ErrMessage\n",
             $FullErrFileName, $Job, $Step, $Task;
}
my $Pid = $TA->Run(["./task"], 0);
if (!$Pid or !defined $TA->Wait($Pid, $Task->Timeout))
{
  $ErrMessage = $TA->GetLastError();
}

if (defined($ErrMessage))
{
  $TA->GetFile("Reconfig.log", $FullRawlogFileName);
  ProcessRawlog($FullRawlogFileName, $FullLogFileName, $FullErrFileName);
  FatalError "Failure running script in VM: $ErrMessage\n",
             $FullErrFileName, $Job, $Step, $Task;
}

if (!$TA->GetFile("Reconfig.log", $FullRawlogFileName))
{
  $ErrMessage = $TA->GetLastError();
  FatalError "Can't copy log from VM: $ErrMessage\n", $FullErrFileName,
             $Job, $Step, $Task;
}
$TA->Disconnect();

my $Success = ProcessRawlog($FullRawlogFileName, $FullLogFileName,
                              $FullErrFileName);
if ($Success)
{
  $ErrMessage = $VM->RemoveSnapshot($VM->IdleSnapshot);
  if (defined($ErrMessage))
  {
    FatalError "Can't remove snapshot: $ErrMessage\n", $FullErrFileName,
               $Job, $Step, $Task;
  }

  $ErrMessage = $VM->CreateSnapshot($VM->IdleSnapshot);
  if (defined($ErrMessage))
  {
    FatalError "Can't take snapshot: $ErrMessage\n", $FullErrFileName,
               $Job, $Step, $Task;
  }

  $VM->Status("idle");
  $Task->Status("completed");
}
else
{
  $Task->Status("failed");
  $VM->Status("dirty");
}

$Task->ChildPid(undef);
$Task->Ended(time);
$Task->Save();
$Job->UpdateStatus();
$VM->Save();

$Task = undef;
$Step = undef;
$Job = undef;

TaskComplete($JobId, $StepNo, $TaskNo);

LogMsg "Task $JobId/$StepNo/$TaskNo completed\n";

exit;
