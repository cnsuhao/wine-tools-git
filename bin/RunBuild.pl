#!/usr/bin/perl -Tw

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

  LogMsg "RunBuild: $JobKey/$StepKey/$TaskKey $ErrMessage";

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
          if ($Line =~ m/^BuildSingleTest: (.*)$/)
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
#    unlink($FullRawlogFileName);
  }

  return $FoundOk;
}

$ENV{PATH} = "/usr/bin:/bin";
delete $ENV{ENV};

my ($JobId, $StepNo, $TaskNo) = @ARGV;
if (! $JobId || ! $StepNo || ! $TaskNo)
{
  die "Usage: RunBuild.pl JobId StepNo TaskNo";
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

LogMsg "RunBuild: task $JobId/$StepNo/$TaskNo started\n";

my $RptFileName = $VM->Name . ".rpt";
my $StepDir = "$DataDir/jobs/$JobId/$StepNo";
my $TaskDir = "$StepDir/$TaskNo";
my $FullRawlogFileName = "$TaskDir/rawlog";
my $FullLogFileName = "$TaskDir/log";
my $FullErrFileName = "$TaskDir/err";

my $DllBaseName;
my $Run64 = !1;
foreach my $StepKey (@{$Job->Steps->GetKeys()})
{
  my $OtherStep = $Job->Steps->GetItem($StepKey);
  if ($OtherStep->No != $StepNo)
  {
    my $OtherFileName = $OtherStep->FileName;
    if ($OtherFileName =~ m/^([\w_\-]+)_test(|64)\.exe$/)
    {
      if (defined($DllBaseName) && $DllBaseName ne $1)
      {
        FatalError "$1 doesn't match previously found $DllBaseName\n",
                   $FullErrFileName, $Job, $Step, $Task;
      }
      $DllBaseName = $1;
      if ($2 eq "64")
      {
        $Run64 = 1;
      }
    }
  }
}
if (! defined($DllBaseName))
{
  FatalError "Can't determine DLL base name\n",
             $FullErrFileName, $Job, $Step, $Task;
}

my $ErrMessage = $Step->HandleStaging($JobId);
if (defined($ErrMessage))
{
  FatalError "$ErrMessage\n",
             $FullErrFileName, $Job, $Step, $Task;
}

$VM->Status('running');
my $ErrProperty;
($ErrProperty, $ErrMessage) = $VM->Save();
if (defined($ErrMessage))
{
  FatalError "Can't set VM status to running: $ErrMessage\n",
             $FullErrFileName, $Job, $Step, $Task;
}
my $FileName = $Step->FileName;
$ErrMessage = $VM->CopyFileFromHostToGuest("$StepDir/$FileName",
                                           "$DataDir/staging/$FileName");
if (defined($ErrMessage))
{
  FatalError "Can't copy exe to VM: $ErrMessage\n",
             $FullErrFileName, $Job, $Step, $Task;
}
my $Script = "#!/bin/sh\n";
$Script .= "$BinDir/BuildSingleTest.pl $FileName $DllBaseName 32";
if ($Run64)
{
  $Script .= ",64";
}
$Script .= "\n";
$ErrMessage = $VM->RunScriptInGuestTimeout("", $Script, $Task->Timeout);
if (defined($ErrMessage))
{
  $VM->CopyFileFromGuestToHost("$LogDir/BuildSingleTest.log",
                               $FullRawlogFileName);
  ProcessRawlog($FullRawlogFileName, $FullLogFileName, $FullErrFileName);
  FatalError "Failure running script in VM: $ErrMessage\n",
             $FullErrFileName, $Job, $Step, $Task;
}

$ErrMessage = $VM->CopyFileFromGuestToHost("$LogDir/BuildSingleTest.log",
                                           $FullRawlogFileName);
if (defined($ErrMessage))
{
  FatalError "Can't copy log from VM: $ErrMessage\n", $FullErrFileName,
             $Job, $Step, $Task;
}
my $NewStatus = ProcessRawlog($FullRawlogFileName, $FullLogFileName,
                              $FullErrFileName) ? "completed" : "failed";

foreach my $StepKey (@{$Job->Steps->GetKeys()})
{
  my $OtherStep = $Job->Steps->GetItem($StepKey);
  if ($OtherStep->No != $StepNo)
  {
    my $OtherFileName = $OtherStep->FileName;
    if ($OtherFileName =~ m/^[\w_\-]+_test(|64)\.exe$/)
    {
      my $OtherStepDir = "$DataDir/jobs/$JobId/" . $OtherStep->No;
      mkdir $OtherStepDir;

      my $Bits = $1;
      if ($Bits eq "")
      {
        $Bits = "32";
      }
      $ErrMessage = $VM->CopyFileFromGuestToHost("$DataDir/build-mingw$Bits/dlls/$DllBaseName/tests/${DllBaseName}_test.exe",
                                                 "$OtherStepDir/$OtherFileName");
      if (defined($ErrMessage))
      {
        FatalError "Can't copy generated executable from VM: $ErrMessage\n",
                   $FullErrFileName, $Job, $Step, $Task;
      }
      chmod 0664, "$OtherStepDir/$OtherFileName";
    }
  }
}

$Task->Status($NewStatus);
$Task->ChildPid(undef);
$Task->Ended(time);
$Task->Save();
$Job->UpdateStatus();
$VM->Status('dirty');
$VM->Save();

$Task = undef;
$Step = undef;
$Job = undef;
$Jobs = undef;

TaskComplete($JobId, $StepNo, $TaskNo);

LogMsg "RunBuild: task $JobId/$StepNo/$TaskNo completed\n";

exit;
