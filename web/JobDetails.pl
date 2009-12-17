# Job details page
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

package JobDetailsPage;

use URI::Escape;
use ObjectModel::PropertyDescriptor;
use ObjectModel::CGI::CollectionPage;
use WineTestBot::Config;
use WineTestBot::Jobs;
use WineTestBot::StepsTasks;

@JobDetailsPage::ISA = qw(ObjectModel::CGI::CollectionPage);

sub _initialize
{
  my $self = shift;

  my $Job = CreateJobs()->GetItem($self->GetParam("Key"));
  if (! defined($Job))
  {
    $self->Redirect("/index.pl");
  }

  $self->{JobId} = $Job->Id;

  $self->SUPER::_initialize(@_, CreateStepsTasks($Job));
}

sub GetTitle()
{
  my $self = shift;

  return "Job " . $self->{JobId};
}

sub DisplayProperty
{
  my $self = shift;
  my ($CollectionBlock, $PropertyDescriptor) = @_;

  my $PropertyName = $PropertyDescriptor->GetName();

  return $PropertyName eq "StepNo" || $PropertyName eq "TaskNo" ||
         $PropertyName eq "Status" || $PropertyName eq "VM" ||
         $PropertyName eq "Timeout" || $PropertyName eq "FileName" ||
         $PropertyName eq "CmdLineArg" || $PropertyName eq "Started" ||
         $PropertyName eq "Ended" || $PropertyName eq "TestFailures";
}

sub GetItemActions
{
  return [];
}

sub GetActions
{
  return [];
}

sub SortKeys
{
  my $self = shift;
  my $CollectionBlock = shift;
  my $Keys = $_[0];

  my @SortedKeys = sort @$Keys;
  return \@SortedKeys;
}

sub GeneratePage
{
  my $self = shift;

  foreach my $Key (@{$self->{Collection}->GetKeys()})
  {
    my $Item = $self->{Collection}->GetItem($Key);
    if ($Item->Status eq "queued" || $Item->Status eq "running")
    {
      $self->{Request}->headers_out->add("Refresh", "30");
      last;
    }
  }

  $self->SUPER::GeneratePage(@_);
}

sub GenerateBody
{
  my $self = shift;

  $self->SUPER::GenerateBody(@_);

  my $Keys = $self->SortKeys(undef, $self->{Collection}->GetKeys());
  foreach my $Key (@$Keys)
  {
    my $Item = $self->{Collection}->GetItem($Key);
    my $TaskDir = "$DataDir/jobs/" . $self->{JobId} . "/" . $Item->StepNo .
                  "/" . $Item->TaskNo;
    my $VM = $Item->VM;
    print "<h2><a name='k", $self->escapeHTML($Key), "'></a>" ,
          $self->escapeHTML($VM->Name), "</h2>\n";
    my $ScreenshotParamName = "scrshot_$Key";
    my $FullLogParamName = "log_$Key";
    my $LogName = "$TaskDir/log";
    my $ErrName = "$TaskDir/err";
    print "<div class='TaskMoreInfoLinks'>\n";
    if ($Item->Status eq "running")
    {
      my $URI = "/Screenshot.pl?VMName=" . uri_escape($VM->Name);
      print "<div class='Screenshot'><img src='" .
            $self->CGI->escapeHTML($URI) . "' alt='Screenshot' /></div>\n";
    }
    elsif (-r "$TaskDir/screenshot.png")
    {
      if (defined($self->GetParam($ScreenshotParamName)))
      {
        my $URI = "/Screenshot.pl?JobKey=" . uri_escape($self->{JobId}) .
                  "&StepKey=" . uri_escape($Item->StepNo) .
                  "&TaskKey=" . uri_escape($Item->TaskNo);
        print "<div class='Screenshot'><img src='" .
              $self->CGI->escapeHTML($URI) . "' alt='Screenshot' /></div>\n";
      }
      else
      {
        my $URI = $ENV{"SCRIPT_NAME"} . "?Key=" . uri_escape($self->{JobId}) .
                  "&$ScreenshotParamName=1";
        if (defined($self->GetParam($FullLogParamName)))
        {
          $URI .= "&$FullLogParamName=1";
        }
        $URI .= "#k" . uri_escape($Key);
        print "<div class='TaskMoreInfoLink'><a href='" .
              $self->CGI->escapeHTML($URI) .
              "'>Show final screenshot</a></div>";
        print "\n";
      }
    }
    my $FullLog = !1;
    if (-r $LogName)
    {
      if (defined($self->GetParam($FullLogParamName)))
      {
        $FullLog = 1;
      }
      else
      {
        my $URI = $ENV{"SCRIPT_NAME"} . "?Key=" . uri_escape($self->{JobId}) .
                  "&$FullLogParamName=1";
        if (defined($self->GetParam($ScreenshotParamName)))
        {
          $URI .= "&$ScreenshotParamName=1";
        }
        $URI .= "#k" . uri_escape($Key);
        print "<div class='TaskMoreInfoLink'><a href='" .
              $self->CGI->escapeHTML($URI) .
              "'>Show full log</a></div>\n";
      }
    }
    print "</div>\n";
    if (open LOGFILE, "<$LogName")
    {
      my $HasLogEntries = !1;
      my $First = 1;
      my $CurrentDll = "";
      my $PrintedDll = "";
      my $Line;
      while (defined($Line = <LOGFILE>))
      {
        $HasLogEntries = 1;
        chomp($Line);
        if ($Line =~ m/^([^:]+):[^ ]+ start [^ ]+ -$/)
        {
          $CurrentDll = $1;
        }
        if ($FullLog || $Line =~ m/: Test failed: / || $Line =~ m/ done \(-/ ||
            $Line =~ m/ done \(258\)/)
        {
          if ($PrintedDll ne $CurrentDll && ! $FullLog)
          {
            if ($First)
            {
              $First = !1;
            }
            else
            {
              print "</code></pre>";
            }
            print "<div class='LogDllName'>$CurrentDll:</div><pre><code>";
            $PrintedDll = $CurrentDll;
          }
          elsif ($First)
          {
            print "<pre><code>";
            $First = !1;
          }
          if (! $FullLog && $Line =~ m/^[^:]+:([^ ]+) done \(-/)
          {
            print "$1: Crashed\n";
          }
          elsif (! $FullLog && $Line =~ m/^[^:]+:([^ ]+) done \(258\)/)
          {
            print "$1: Timeout\n";
          }
          else
          {
            print $self->escapeHTML($Line), "\n";
          }
        }
      }
      close LOGFILE;

      if (open ERRFILE, "<$ErrName")
      {
        if (! $First)
        {
          print "</code></pre>\n";
          $First = 1;
        }
        while (defined($Line = <ERRFILE>))
        {
          $HasLogEntries = 1;
          chomp($Line);
          if ($First)
          {
            print "<br>\n";
            print "<pre><code>";
            $First = !1;
          }
          print $self->escapeHTML($Line), "\n";
        }
        close ERRFILE;
      }

      if (! $First)
      {
        print "</code></pre>\n";
      }
      else
      {
        print $HasLogEntries ? "No test failures found" : "Empty log";
      }
    }
    elsif (open ERRFILE, "<$ErrName")
    {
      my $HasErrEntries = !1;
      my $Line;
      while (defined($Line = <ERRFILE>))
      {
        chomp($Line);
        if (! $HasErrEntries)
        {
          print "<pre><code>";
          $HasErrEntries = 1;
        }
        print $self->escapeHTML($Line), "\n";
      }
      close LOGFILE;
      if ($HasErrEntries)
      {
        print "</code></pre>\n";
      }
      else
      {
        print "Empty log";
      }
      close ERRFILE;
    }
    else
    {
      print "<p>No log available yet</p>\n";
    }
  }
}

sub GenerateDataCell
{
  my $self = shift;
  my ($CollectionBlock, $Item, $PropertyDescriptor, $DetailsPage) = @_;

  if ($PropertyDescriptor->GetName() eq "VM")
  {
    print "<td><a href='#k", $self->escapeHTML($Item->GetKey()), "'>";
    print $self->escapeHTML($self->GetDisplayValue($CollectionBlock, $Item,
                                                   $PropertyDescriptor));
    print "</a></td>\n";
  }
  else
  {
    $self->SUPER::GenerateDataCell(@_);
  }
}

package main;

my $Request = shift;

my $JobDetailsPage = JobDetailsPage->new($Request, "");
$JobDetailsPage->GeneratePage();
