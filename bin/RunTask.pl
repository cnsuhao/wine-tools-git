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

  LogMsg "RunTask: $JobKey/$StepKey/$TaskKey $ErrMessage";

  if ($Task)
  {
    $Task->Status("failed");
    $Task->Ended(time);
    $Task->Save();
    $Job->UpdateStatus();

    if ($Task->VM->Type eq "extra")
    {
      $Task->VM->PowerOff();
    }
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

    if ($Task && $Step->Type eq "suite")
    {
      my $LatestName = "$DataDir/latest/" . $Task->VM->Name . "_" .
                       ($Task->VM->Bits == 64 &&
                        $Step->FileName eq "winetest64-latest.exe" ? "64" :
                                                                     "32") .
                       ".err";
      unlink($LatestName);
      link($RptFileName, $LatestName);
    }
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

  my $Failures;
  my $Line;
  while (defined($Line = <REPORTFILE>))
  {
    if ($Line =~ m/: \d+ tests? executed \(\d+ marked as todo, (\d+) failures?\), \d+ skipped\./)
    {
      $Failures += $1;
    }
    elsif ($Line =~ m/ done \(-/ || $Line =~ m/ done \(258\)/)
    {
      $Failures++;
    }
  }
  close REPORTFILE;

  return $Failures;
}

sub RetrieveLogFile
{
  my ($Job, $Step, $Task, $GuestLogFileName, $HostLogFileName) = @_;

  my $VM = $Task->VM;
  my $ErrMessage = $VM->CopyFileFromGuestToHost($GuestLogFileName,
                                                $HostLogFileName);
  chmod 0664, $HostLogFileName;
  if (defined($ErrMessage) || $Step->Type ne "suite")
  {
    return $ErrMessage;
  }

  my $LatestNameBase = "$DataDir/latest/" . $VM->Name . "_" .
                       ($VM->Bits == 64 &&
                        $Step->FileName eq "winetest64-latest.exe" ?
                        "64" : "32");
  unlink("${LatestNameBase}.log");
  unlink("${LatestNameBase}.err");
  link("$DataDir/jobs/" . $Job->Id . "/" . $Step->No . "/" . $Task->No . "/log",
       "${LatestNameBase}.log");

  return undef;
}

$ENV{PATH} = "/usr/bin:/bin";
delete $ENV{ENV};

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
my $FullLogFileName = "$TaskDir/log";
my $FullErrFileName = "$TaskDir/err";
my $FullScreenshotFileName = "$TaskDir/screenshot.png";

sub TermHandler
{
  RetrieveLogFile $Job, $Step, $Task, "C:\\winetest\\$RptFileName",
                  $FullLogFileName;
  TakeScreenshot $VM, $FullScreenshotFileName;
  FatalError "Cancelled\n", $FullErrFileName, $Job, $Step, $Task;
}

$VM->Status('running');
$SIG{TERM} = \&TermHandler;
my ($ErrProperty, $ErrMessage) = $VM->Save();
if (defined($ErrMessage))
{
  FatalError "Can't set VM status to running: $ErrMessage\n",
             $FullErrFileName, $Job, $Step, $Task;
}
my $FileName = $Step->FileName;
$ErrMessage = $VM->CopyFileFromHostToGuest("$StepDir/$FileName",
                                           "C:\\winetest\\$FileName");
if (defined($ErrMessage))
{
  FatalError "Can't copy exe to VM: $ErrMessage\n",
             $FullErrFileName, $Job, $Step, $Task;
}
my $Script = "\@cd \\winetest\r\n\@set WINETEST_DEBUG=" . $Step->DebugLevel .
             "\r\n";
if ($Step->ReportSuccessfulTests)
{
  $Script .= "\@set WINETEST_REPORT_SUCCESS=1\r\n";
}
$Script .= "\@$FileName ";
if ($Step->Type eq "single")
{
  my $CmdLineArg = $Task->CmdLineArg;
  if ($CmdLineArg)
  {
    $Script .= "$CmdLineArg ";
  }
  $Script .= "> $RptFileName\r\n";
}
elsif ($Step->Type eq "suite")
{
  my $Tag = lc($TagPrefix) . "-" . lc($VM->Name);
  $Tag =~ s/[^a-zA-Z0-9]/-/g;
  if ($VM->Bits == 64)
  {
    $Tag .= "-" . ($FileName eq "winetest64-latest.exe" ? "64" : "32");
  }
  $Script .= "-q -o $RptFileName -t $Tag -m $AdminEMail\r\n" .
             "\@$FileName -q -s $RptFileName\r\n";
}

# Needed to exit the command prompt on Win9x/WinMe
$Script .= "\@exit";

$ErrMessage = $VM->RunScriptInGuestTimeout("", $Script, $Task->Timeout);
if (defined($ErrMessage))
{
  RetrieveLogFile $Job, $Step, $Task, "C:\\winetest\\$RptFileName",
                  $FullLogFileName;
  TakeScreenshot $VM, $FullScreenshotFileName;
  FatalError "Failure running script in VM: $ErrMessage\n",
             $FullErrFileName, $Job, $Step, $Task;
}
TakeScreenshot $VM, $FullScreenshotFileName;

$ErrMessage = RetrieveLogFile $Job, $Step, $Task, "C:\\winetest\\$RptFileName",
                              $FullLogFileName;
if (defined($ErrMessage))
{
  FatalError "Can't copy log from VM: $ErrMessage\n", $FullErrFileName,
             $Job, $Step, $Task;
}

$Task->Status("completed");
$Task->ChildPid(undef);
$Task->Ended(time);
my $TestFailures = CountFailures($FullLogFileName);
if (defined($TestFailures))
{
  $Task->TestFailures($TestFailures);
}
else
{
  my $OldUMask = umask(002);
  if (open ERRFILE, ">>$FullErrFileName")
  {
    print ERRFILE "No test summary line found\n";
    close ERRFILE;
  }
  umask($OldUMask);
}
$Task->Save();
$Job->UpdateStatus();
if ($Task->VM->Type eq "extra")
{
  $Task->VM->PowerOff();
}
$VM->Status('dirty');
$VM->Save();

$Task = undef;
$Step = undef;
$Job = undef;
$Jobs = undef;

TaskComplete($JobId, $StepNo, $TaskNo);

LogMsg "RunTask: task $JobId/$StepNo/$TaskNo (" . $VM->Name . ") completed\n";

exit;
