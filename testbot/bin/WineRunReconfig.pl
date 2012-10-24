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

my $Dir;
sub BEGIN
{
  $0 =~ m=^(.*)/[^/]*$=;
  $Dir = $1;
}
use lib "$Dir/../lib";

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

  LogMsg "$JobKey/$StepKey/$TaskKey $ErrMessage";

  if ($Task)
  {
    $Task->Status("failed");
    $Task->Ended(time);
    $Task->Save();
    $Job->UpdateStatus();

    $Task->VM->Status('dirty');
    $Task->VM->Save();
  }

  if ($RptFileName)
  {
    my $RPTFILE;
    if (open RPTFILE, ">>$RptFileName")
    {
      print RPTFILE $ErrMessage;
      close RPTFILE;
    }
  }

  TaskComplete($JobKey, $StepKey, $TaskKey);

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

umask(002);
mkdir "$DataDir/jobs/$JobId";
mkdir "$DataDir/jobs/$JobId/$StepNo";
mkdir "$DataDir/jobs/$JobId/$StepNo/$TaskNo";

my $VM = $Task->VM;

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
my $Script = "#!/bin/sh\n$BinDir/build/Reconfig.pl\n";
$ErrMessage = $VM->RunScriptInGuestTimeout($Script, $Task->Timeout);
if (defined($ErrMessage))
{
  $VM->CopyFileFromGuestToHost("$LogDir/Reconfig.log",
                               $FullRawlogFileName);
  ProcessRawlog($FullRawlogFileName, $FullLogFileName, $FullErrFileName);
  FatalError "Failure running script in VM: $ErrMessage\n",
             $FullErrFileName, $Job, $Step, $Task;
}

$ErrMessage = $VM->CopyFileFromGuestToHost("$LogDir/Reconfig.log",
                                           $FullRawlogFileName);
if (defined($ErrMessage))
{
  FatalError "Can't copy log from VM: $ErrMessage\n", $FullErrFileName,
             $Job, $Step, $Task;
}
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
$Jobs = undef;

TaskComplete($JobId, $StepNo, $TaskNo);

LogMsg "Task $JobId/$StepNo/$TaskNo completed\n";

exit;
