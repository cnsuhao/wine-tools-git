#!/usr/bin/perl -Tw
#
# Sends the job log to the submitting user and informs the Wine Patches web
# site of the test results.
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

use Algorithm::Diff;
use WineTestBot::Config;
use WineTestBot::Jobs;
use WineTestBot::Log;
use WineTestBot::StepsTasks;

sub FatalError
{
  my ($ErrMessage, $Job) = @_;

  my $JobKey = defined($Job) ? $Job->GetKey() : "0";

  LogMsg "$JobKey $ErrMessage";

  exit 1;
}

sub IsBotFailure
{
  my $ErrLine = $_[0];

  return ($ErrLine =~ m/Cancelled/ ||
          $ErrLine =~ m/Can't set VM status to running/ ||
          $ErrLine =~ m/Can't copy exe to VM/ ||
          $ErrLine =~ m/Can't copy log from VM/ ||
          $ErrLine =~ m/Can't copy generated executable from VM/);
}

sub CheckErrLog
{
  my $ErrLogFileName = $_[0];

  my $BotFailure = !1;
  my $Messages = "";
  if (open ERRFILE, "$ErrLogFileName")
  {
    my $Line;
    while (defined($Line = <ERRFILE>))
    {
      if (IsBotFailure($Line))
      {
        if (! $Messages)
        {
          $BotFailure = 1;
        }
      }
      else
      {
        $Messages .= $Line;
      }
    }
    close ERRFILE;
  }

  return ($BotFailure, $Messages);
}

sub ReadLog
{
  my ($LogName, $BaseName, $TestSet) = @_;

  my @Messages;
  if (open LOG, "<$LogName")
  {
    my $Line;
    my $Found = !1;
    while (! $Found && defined($Line = <LOG>))
    {
      $Found = ($Line =~ m/${BaseName}:${TestSet} start/);
    }
    if ($Found)
    {
      $Found = !1;
      while (! $Found && defined($Line = <LOG>))
      {
        $Line =~ s/[\r\n]*$//;
        if ($Line =~ m/${BaseName}:${TestSet} done/)
        {
          if ($Line =~ m/${BaseName}:${TestSet} done \((\d+)\)/ &&
              $1 eq "258")
          {
            $Messages[@Messages] = "Timeout";
          }
          $Found = 1;
        }
        else
        {
          $Messages[@Messages] = $Line;
        }
      }
    }

    close LOG;
  }
  else
  {
    LogMsg "Unable to open log $LogName\n";
  }

  return \@Messages;
}

sub GetLineKey
{
  my $Line = $_[0];

  $Line =~ s/^([\w_.]+:)\d+(:.*)$/$1$2/;

  return $Line;
}

sub CompareLogs
{
  my ($SuiteLog, $TaskLog, $BaseName, $TestSet) = @_;

  my $Messages = "";

  my $SuiteMessages = ReadLog($SuiteLog, $BaseName, $TestSet);
  my $TaskMessages = ReadLog($TaskLog, $BaseName, $TestSet);

  my $Diff = Algorithm::Diff->new($SuiteMessages, $TaskMessages,
                                  { keyGen => \&GetLineKey });
  while ($Diff->Next())
  {
    if (! $Diff->Same())
    {
      foreach my $Line ($Diff->Items(2))
      {
        if ($Line =~ m/: Test failed: / || 
            $Line =~ m/: unhandled exception [0-9a-fA-F]{8} at / ||
            $Line =~ m/Timeout/i)
        {
          $Messages .= "$Line\n";
        }
      }
    }
  }

  return $Messages;
}

sub SendLog
{
  my $Job = shift;
  my $To = $WinePatchToOverride || $Job->GetEMailRecipient();
  if (! defined($To))
  {
    return;
  }

  my $StepsTasks = CreateStepsTasks($Job);
  my @SortedKeys = sort @{$StepsTasks->GetKeys()};

  open (SENDMAIL, "|/usr/sbin/sendmail -oi -t -odq");
  print SENDMAIL "From: Marvin <$RobotEMail>\n";
  print SENDMAIL "To: $To\n";
  my $Subject = "TestBot job " . $Job->Id . " results";
  my $Description = $Job->GetDescription();
  if ($Description)
  {
    $Subject .= ": " . $Description;
  }
  print SENDMAIL "Subject: $Subject\n";
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

  my @FailureKeys;
  foreach my $Key (@SortedKeys)
  {
    my $StepTask = $StepsTasks->GetItem($Key);

    print SENDMAIL "\n=== ", $StepTask->GetTitle(), " ===\n";

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
        if ($Line =~ m/: Test failed: / || $Line =~ m/ done \(258\)/ ||
            $Line =~ m/: unhandled exception [0-9a-fA-F]{8} at /)
        {
          if ($PrintedDll ne $CurrentDll)
          {
            print SENDMAIL "\n$CurrentDll:\n";
            $PrintedDll = $CurrentDll;
          }
          if ($Line =~ m/^[^:]+:([^ ]+) done \(258\)/)
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
        if (! $HasLogEntries)
        {
          print SENDMAIL "Empty log\n";
        }
        elsif ($StepTask->Type eq "build")
        {
          print SENDMAIL "No build failures found\n";
        }
        else
        {
          print SENDMAIL "No test failures found\n";
        }
      }
      else
      {
        $FailureKeys[scalar @FailureKeys] = $Key;
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
      else
      {
        $FailureKeys[scalar @FailureKeys] = $Key;
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

  if (! defined($Job->Patch))
  {
    return;
  }

  my $Messages = "";
  foreach my $Key (@FailureKeys)
  {
    my $StepTask = $StepsTasks->GetItem($Key);

    my $TaskDir = "$DataDir/jobs/" . $Job->Id . "/" . $StepTask->StepNo .
                  "/" . $StepTask->TaskNo;

    my ($BotFailure, $MessagesFromErr) = CheckErrLog("$TaskDir/err");
    if (! $BotFailure)
    {
      my $Bits = ($StepTask->FileName =~ /_test64\.exe$/ ? 64 : 32);
      my $LatestName = "$DataDir/latest/" . $StepTask->VM->Name . "_$Bits";
      my ($LatestBotFailure, $Dummy) = CheckErrLog("$LatestName.err");
      my $MessagesFromLog = "";
      if (! $LatestBotFailure)
      {
        if (defined($StepTask->CmdLineArg))
        {
          $StepTask->FileName =~ m/^(.*)_test(64)?\.exe/;
          $MessagesFromLog = CompareLogs("$LatestName.log", "$TaskDir/log",
                                         $1, $StepTask->CmdLineArg);
        }
      }
      else
      {
        LogMsg "BotFailure found in ${LatestName}.err\n";
      }
      if ($MessagesFromErr || $MessagesFromLog)
      {
        $Messages .= "\n=== " . $StepTask->GetTitle() . " ===\n" .
                     $MessagesFromLog . $MessagesFromErr;
      }
    }
    elsif ($BotFailure)
    {
      LogMsg "BotFailure found in $TaskDir/err\n";
    }
  }

  if ($Messages)
  {
    open (SENDMAIL, "|/usr/sbin/sendmail -oi -t -odq");
    print SENDMAIL "From: Marvin <$RobotEMail>\n";
    print SENDMAIL "To: $To\n";
    print SENDMAIL "Cc: $WinePatchCc\n";
    print SENDMAIL "Subject: Re: ", $Job->Patch->Subject, "\n";
    print SENDMAIL <<"EOF";

Hi,

While running your changed tests on Windows, I think I found new failures.
Being a bot and all I'm not very good at pattern recognition, so I might be
wrong, but could you please double-check?
Full results can be found at
EOF
    print SENDMAIL "http://$WebHostName/JobDetails.pl?Key=",
                   $Job->GetKey(), "\n\n";
    print SENDMAIL "Your paranoid android.\n\n";

    print SENDMAIL $Messages;
    close SENDMAIL;
  }

  if (defined($PatchResultsEMail))
  {
    my $Patch = $Job->Patch;
    open (SENDMAIL, "|/usr/sbin/sendmail -oi -t -odq");
    print SENDMAIL "From: Marvin <$RobotEMail>\n";
    print SENDMAIL "To: $PatchResultsEMail\n";
    print SENDMAIL "X-TestBot-Results: ", $Patch->WebPatchId,
          ($Messages ? " failed\n" : " passed\n");
    print SENDMAIL "Subject: TestBot results for patch ", $Patch->WebPatchId,
          ($Messages ? ": Failed\n" : ": Passed\n");
    print SENDMAIL "\n";
    print SENDMAIL "--- BEGIN GENERAL ---\n";
    print SENDMAIL "Patch: ", $Patch->WebPatchId, "\n";
    print SENDMAIL "Patch-Subject: ", $Patch->Subject, "\n";
    print SENDMAIL "Test-Result: ", $Messages ? "Failed" : "Passed", "\n";
    print SENDMAIL "--- END GENERAL ---\n";
    print SENDMAIL "--- BEGIN NEW_ERRORS ---\n";
    if ($Messages)
    {
      print SENDMAIL $Messages;
    }
    print SENDMAIL "--- END NEW_ERRORS ---\n";
    print SENDMAIL "--- BEGIN FULL_LOGS ---\n";
    foreach my $Key (@SortedKeys)
    {
      my $StepTask = $StepsTasks->GetItem($Key);

      print SENDMAIL "\n=== ", $StepTask->GetTitle(), " ===\n";

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
    print SENDMAIL "--- END FULL_LOGS ---\n";
  }
}

$ENV{PATH} = "/usr/bin:/bin";
delete $ENV{ENV};

my $JobId = $ARGV[0];
if (! $JobId)
{
  die "Usage: WineSendLog.pl JobId";
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

my $Job = CreateJobs()->GetItem($JobId);
if (! defined($Job))
{
  FatalError "Job $JobId doesn't exist\n";
}

SendLog($Job);

LogMsg "Log for job $JobId sent\n";

exit;
