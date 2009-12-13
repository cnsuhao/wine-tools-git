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
use WineTestBot::Engine::Notify;

sub FatalError
{
  my ($ErrMessage, $RptFileName, $Job, $Step, $Task) = @_;

  my $JobKey = defined($Job) ? $Job->GetKey() : "0";
  my $StepKey = defined($Step) ? $Step->GetKey() : "0";
  my $TaskKey = defined($Task) ? $Task->GetKey() : "0";

  LogMsg "RunTask: $JobKey/$StepKey/$TaskKey $ErrMessage";

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
    my $OldUMask = umask(002);
    if (open RPTFILE, ">>$RptFileName")
    {
      print RPTFILE $ErrMessage;
      close RPTFILE;
    }
    umask($OldUMask);
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
      LogMsg "RunTask: Can't save screenshot: $!\n";
    }
  }
  else
  {
    LogMsg "RunTask: Can't capture screenshot: $ErrMessage\n";
  }
}

sub CountFailures
{
  my $ReportFileName = $_[0];

  if (! open REPORTFILE, "<$ReportFileName")
  {
    return undef;
  }

  my $Failures = 0;
  my $Line;
  while (defined($Line = <REPORTFILE>))
  {
    if ($Line =~ m/: Test failed: / || $Line =~ m/ done \(-/)
    {
      $Failures++;
    }
  }
  close REPORTFILE;

  return $Failures;
}

my ($JobId, $StepNo, $TaskNo) = @ARGV;
if (! $JobId || ! $StepNo || ! $TaskNo)
{
  die "Usage: RunTask.pl JobId StepNo TaskNo";
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

LogMsg "RunTask: task $JobId/$StepNo/$TaskNo (" . $VM->Name . ") started\n";

my $RptFileName = $VM->Name . ".rpt";
my $StepDir = "$DataDir/jobs/$JobId/$StepNo";
my $TaskDir = "$StepDir/$TaskNo";
my $FullRptFileName = "$TaskDir/log";
my $FullScreenshotFileName = "$TaskDir/screenshot.png";

$VM->Status('running');
my ($ErrProperty, $ErrMessage) = $VM->Save();
if (defined($ErrMessage))
{
  FatalError "Can't set VM status to running: $ErrMessage\n",
             $FullRptFileName, $Job, $Step, $Task;
}
my $FileName = $Step->FileName;
$ErrMessage = $VM->CopyFileFromHostToGuest("$StepDir/$FileName",
                                           "C:\\winetest\\$FileName");
if (defined($ErrMessage))
{
  FatalError "Can't copy exe to VM: $ErrMessage\n",
             $FullRptFileName, $Job, $Step, $Task;
}
my $Script = "\@cd \\winetest\r\n\@$FileName ";
if ($Task->Type eq "single")
{
  my $CmdLineArg = $Task->CmdLineArg;
  if ($CmdLineArg)
  {
    $Script .= "$CmdLineArg ";
  }
  $Script .= "> $RptFileName\r\n";
}
elsif ($Task->Type eq "suite")
{
  $Script .= "-q -o $RptFileName -t wtb-" . lc($VM->Name) . "\r\n" .
             "\@$FileName -q -s $RptFileName\r\n";
}
$ErrMessage = $VM->RunScriptInGuestTimeout("", $Script, $Task->Timeout);
if (defined($ErrMessage))
{
  $VM->CopyFileFromGuestToHost("C:\\winetest\\$RptFileName",
                               $FullRptFileName);
  TakeScreenshot $VM, $FullScreenshotFileName;
  chmod 0664, $FullRptFileName;
  FatalError "Failure running script in VM: $ErrMessage\n",
             $FullRptFileName, $Job, $Step, $Task;
}
TakeScreenshot $VM, $FullScreenshotFileName;

$ErrMessage = $VM->CopyFileFromGuestToHost("C:\\winetest\\$RptFileName",
                                           $FullRptFileName);
chmod 0664, $FullRptFileName;
if (defined($ErrMessage))
{
  FatalError "Can't copy log from VM: $ErrMessage\n", $FullRptFileName,
             $Job, $Step, $Task;
}

$Task->Status("completed");
$Task->ChildPid(undef);
$Task->Ended(time);
$Task->TestFailures(CountFailures($FullRptFileName));
$Task->Save();
$Job->UpdateStatus();
$VM->Status('dirty');
$VM->Save();

$Task = undef;
$Step = undef;
$Job = undef;
$Jobs = undef;

TaskComplete($JobId, $StepNo, $TaskNo);

LogMsg "RunTask: task $JobId/$StepNo/$TaskNo (" . $VM->Name . ") completed\n";

exit;
