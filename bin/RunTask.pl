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

    if (! $Task->VM->BaseOS)
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

sub SendLog
{
  my $Job = shift;
  if ($Job->User->EMail eq "/dev/null")
  {
    return;
  }

  my $StepsTasks = CreateStepsTasks($Job);
  my @SortedKeys = sort @{$StepsTasks->GetKeys()};

#  open (SENDMAIL, "|/bin/cat");
  open (SENDMAIL, "|/usr/sbin/sendmail -oi -t -odq");
  print SENDMAIL "From: <$RobotEMail> (Marvin)\n";
  print SENDMAIL "To: ", $Job->User->GetEMailRecipient(), "\n";
  print SENDMAIL "Subject: WineTestBot job ", $Job->Id, " finished\n";
  print SENDMAIL <<"EOF";
MIME-Version: 1.0
Content-Type: multipart/mixed; boundary="==13F70BD1-BA1B-449A-9CCB-B6A8E90CED47=="

--==13F70BD1-BA1B-449A-9CCB-B6A8E90CED47==
Content-Type: text/plain; charset="UTF-8"
MIME-Version: 1.0
Content-Transfer-Encoding: 8bit
Content-Disposition: inline

VM                   Status    Number of test failures
EOF
  foreach my $Key (@SortedKeys)
  {
    my $StepTask = $StepsTasks->GetItem($Key);
    my $TestFailures = $StepTask->TestFailures;
    if (! defined($TestFailures))
    {
      $TestFailures = "";
    }
    printf SENDMAIL "%-20s %-9s %s\n", $StepTask->VM->Name, $StepTask->Status,
                    $TestFailures;
  }

  foreach my $Key (@SortedKeys)
  {
    my $StepTask = $StepsTasks->GetItem($Key);

    print SENDMAIL "\n=== ", $StepTask->VM->Name, " (",
                   $StepTask->VM->Description, ") ===\n";

    my $TaskDir = "$DataDir/jobs/" . $Job->Id . "/" . $StepTask->StepNo .
                  "/" . $StepTask->TaskNo;
    if (open LOGFILE, "<$TaskDir/log")
    {
      my $HasLogEntries = !1;
      my $PrintedSomething = !1;
      my $CurrentDll = "";
      my $PrintedDll = "";
      my $Line;
      while (defined($Line = <LOGFILE>))
      {
        $HasLogEntries = 1;
        $Line =~ s/\s*$//;
        if ($Line =~ m/^([^:]+):[^ ]+ start [^ ]+ -$/)
        {
          $CurrentDll = $1;
        }
        if ($Line =~ m/: Test failed: / || $Line =~ m/ done \(-/ ||
            $Line =~ m/ done \(258\)/)
        {
          if ($PrintedDll ne $CurrentDll)
          {
            print SENDMAIL "\n$CurrentDll:\n";
            $PrintedDll = $CurrentDll;
          }
          if ($Line =~ m/^[^:]+:([^ ]+) done \(-/)
          {
            print SENDMAIL "$1: Crashed\n";
          }
          elsif ($Line =~ m/^[^:]+:([^ ]+) done \(258\)/)
          {
            print SENDMAIL "$1: Timeout\n";
          }
          else
          {
            print SENDMAIL "$Line\n";
          }
          $PrintedSomething = 1;
        }
      }
      close LOGFILE;

      if (open ERRFILE, "<$TaskDir/err")
      {
        my $First = 1;
        while (defined($Line = <ERRFILE>))
        {
          if ($First)
          {
            print SENDMAIL "\n";
            $First = !1;
          }
          $HasLogEntries = 1;
          $Line =~ s/\s*$//;
          print SENDMAIL "$Line\n";
          $PrintedSomething = 1;
        }
        close ERRFILE;
      }

      if (! $PrintedSomething)
      {
        print SENDMAIL $HasLogEntries ? "No test failures found\n" : "Empty log\n";
      }
    }
    elsif (open ERRFILE, "<$TaskDir/err")
    {
      my $HasErrEntries = !1;
      my $Line;
      while (defined($Line = <ERRFILE>))
      {
        $HasErrEntries = 1;
        $Line =~ s/\s*$//;
        print SENDMAIL "$Line\n";
      }
      close ERRFILE;
      if (! $HasErrEntries)
      {
        print "Empty log";
      }
    }
  }

  foreach my $Key (@SortedKeys)
  {
    my $StepTask = $StepsTasks->GetItem($Key);

    print SENDMAIL <<"EOF";
--==13F70BD1-BA1B-449A-9CCB-B6A8E90CED47==
Content-Type: text/plain; charset="UTF-8"
MIME-Version: 1.0
Content-Transfer-Encoding: 8bit
EOF
    print SENDMAIL "Content-Disposition: attachment; filename=",
                   $StepTask->VM->Name, ".log\n\n";

    my $TaskDir = "$DataDir/jobs/" . $Job->Id . "/" . $StepTask->StepNo .
                  "/" . $StepTask->TaskNo;

    my $PrintSeparator = !1;
    if (open LOGFILE, "<$TaskDir/log")
    {
      my $Line;
      while (defined($Line = <LOGFILE>))
      {
        $Line =~ s/\s*$//;
        print SENDMAIL "$Line\n";
        $PrintSeparator = 1;
      }
      close LOGFILE;
    }

    if (open ERRFILE, "<$TaskDir/err")
    {
      my $Line;
      while (defined($Line = <ERRFILE>))
      {
          if ($PrintSeparator)
          {
            print SENDMAIL "\n";
            $PrintSeparator = !1;
          }
        $Line =~ s/\s*$//;
        print SENDMAIL "$Line\n";
      }
      close ERRFILE;
    }
  }
  
  print SENDMAIL "--==13F70BD1-BA1B-449A-9CCB-B6A8E90CED47==--\n";
  close(SENDMAIL);
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

$VM->Status('running');
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
                               $FullLogFileName);
  TakeScreenshot $VM, $FullScreenshotFileName;
  chmod 0664, $FullLogFileName;
  FatalError "Failure running script in VM: $ErrMessage\n",
             $FullErrFileName, $Job, $Step, $Task;
}
TakeScreenshot $VM, $FullScreenshotFileName;

$ErrMessage = $VM->CopyFileFromGuestToHost("C:\\winetest\\$RptFileName",
                                           $FullLogFileName);
chmod 0664, $FullLogFileName;
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
if (! $Task->VM->BaseOS)
{
  $Task->VM->PowerOff();
}
$VM->Status('dirty');
$VM->Save();

SendLog($Job);

$Task = undef;
$Step = undef;
$Job = undef;
$Jobs = undef;

TaskComplete($JobId, $StepNo, $TaskNo);

LogMsg "RunTask: task $JobId/$StepNo/$TaskNo (" . $VM->Name . ") completed\n";

exit;
