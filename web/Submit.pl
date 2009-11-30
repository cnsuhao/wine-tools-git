# WineTestBot logout page
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

require "Config.pl";

package SubmitPage1;

use CGI qw(:standard);
use IO::Handle;
use ObjectModel::BasicPropertyDescriptor;
use ObjectModel::CGI::FreeFormPage;
use WineTestBot::Config;
use WineTestBot::Jobs;
use WineTestBot::Engine::Notify;
use WineTestBot::Utils;
use WineTestBot::VMs;

@SubmitPage1::ISA = qw(ObjectModel::CGI::FreeFormPage);

sub _initialize
{
  my $self = shift;

  my @PropertyDescriptors;
  $PropertyDescriptors[0] = CreateBasicPropertyDescriptor("CmdLineArg", "Command line arguments", !1, !1, "A", 50);
  $PropertyDescriptors[1] = CreateBasicPropertyDescriptor("Remarks", "Remarks", !1, !1, "A", 50);

  $self->{Page} = $self->GetParam("Page") || 1;
  if ($self->{Page} == 2)
  {
    $self->{ShowAll} = defined($self->GetParam("ShowAll"));
  }

  $self->SUPER::_initialize(\@PropertyDescriptors);
}

sub GetTitle
{
  return "Submit a job";
}

sub GetHeaderText
{
  my $self = shift;

  if ($self->{Page} == 1)
  {
    return "Specify the test executable (must be a valid Windows .exe file) " .
           "that you want to upload and submit.<br>\n" .
           "To execute e.g. the kernel32 console test set, you'd upload " .
           "<b>kernel32_crosstest.exe</b> and set Command line arguments to " .
           "<b>console</b><br>\n";
           "You can also add some remarks to keep track of this job.";
  }
  elsif ($self->{Page} == 2)
  {
    return "Select the VMs on which you want to run your test";
  }
  elsif ($self->{Page} == 3)
  {
    return "Your job was successfully queued, but the job engine that takes " .
           "care of actually running it seems to be unavailable (perhaps it " .
           "crashed). Your job will remain queued until the engine is " .
           "restarted.";
  }

  return "";
}

sub GenerateFields
{
  my $self = shift;

  print "<div><input type='hidden' name='Page' value='", $self->{Page},
        "'></div>\n";
  if ($self->{Page} == 1)
  {
    print "<div class='ItemProperty'><label>File</label>",
          "<div class='ItemValue'>",
          "<input type='file' name='File' size='50' />",
          "&nbsp;<span class='Required'>*</span></div></div>\n";
    $self->{HasRequired} = 1;
  }
  elsif ($self->{Page} == 2)
  {
    if (! defined($self->{FileName}))
    {
      $self->{FileName} = $self->GetParam("FileName");
    }
    print "<div><input type='hidden' name='CmdLineArg' value='",
          $self->CGI->escapeHTML($self->GetParam("CmdLineArg")), "'></div>\n";
    print "<div><input type='hidden' name='Remarks' value='",
          $self->CGI->escapeHTML($self->GetParam("Remarks")), "'></div>\n";
    print "<div><input type='hidden' name='FileName' value='",
          $self->{FileName}, "'></div>\n";
    if ($self->{ShowAll})
    {
      print "<div><input type='hidden' name='ShowAll' value='1'></div>\n";
    }

    my $NewPage = ($self->GetParam("Page") != 2);
    my $VMs = CreateVMs();
    if (! $self->{ShowAll})
    {
      $VMs->AddFilter("BaseOS", [1]);
    }
    my $SortedKeys = $VMs->SortKeysBySortOrder($VMs->GetKeys());
    foreach my $VMKey (@$SortedKeys)
    {
      my $VM = $VMs->GetItem($VMKey);
      my $FieldName = "vm_" . $self->CGI->escapeHTML($VM->GetKey());
      print "<div class='ItemProperty'><label>",
            $self->CGI->escapeHTML($VM->Name);
      if ($VM->Description)
      {
        print " (", $self->CGI->escapeHTML($VM->Description), ")";
      }
      print "</label><div class='ItemValue'><input type='checkbox' name='$FieldName'";
      if ($NewPage || $self->GetParam($FieldName))
      {
        print " checked='checked'";
      }
      print "/></div></div>\n";
    }
  }
  elsif ($self->{Page} == 3)
  {
    if ($self->GetParam("JobKey"))
    {
      $self->{JobKey} = $self->GetParam("JobKey");
    }
    print "<div><input type='hidden' name='JobKey' value='", $self->{JobKey},
          "'></div>\n";
  }

  $self->SUPER::GenerateFields(@_);
}

sub GenerateActions
{
  my $self = shift;

  if ($self->{Page} == 2)
  {
    print <<EOF;
<script type='text/javascript'>
<!--
function ToggleAll()
{
  for (var i = 0; i < document.forms[0].elements.length; i++)
  {
    if(document.forms[0].elements[i].type == 'checkbox')
      document.forms[0].elements[i].checked = !(document.forms[0].elements[i].checked);
  }
}

// Only put javascript link in document if javascript is enabled
document.write("<div class='ItemActions'><a href='javascript:void(0)' onClick='ToggleAll();'>Toggle All<\\\/a><\\\/div>");
//-->
</script>
EOF

    print "<div class='ItemActions'>\n";
    print "<input type='submit' name='Action' value='",
          $self->{ShowAll} ? "Show base VMs" : "Show all VMs", "'/>\n";
    print "</div>\n";
  }

  $self->SUPER::GenerateActions();
}

sub GetActions
{
  my $self = shift;

  my $Actions = $self->SUPER::GetActions();
  if ($self->{Page} == 1)
  {
    push(@$Actions, "Next >");
  }
  elsif ($self->{Page} == 2)
  {
    push(@$Actions, "< Prev", "Submit");
  }
  elsif ($self->{Page} == 3)
  {
    push(@$Actions, "OK");
  }

  return $Actions;
}

sub DisplayProperty
{
  my $self = shift;

  if ($self->{Page} == 2 || $self->{Page} == 3)
  {
    return "";
  }

  return $self->SUPER::DisplayProperty(@_);
}

sub GetStagingFileName
{
  my $self = shift;
  my $FileName = $_[0];

  if (! $FileName)
  {
    return undef;
  }

  return "$DataDir/staging/" . $self->GetCurrentSession()->Id . "_$FileName";
}

sub Validate
{
  my $self = shift;

  if ($self->{Page} == 2 && $self->GetParam("Page") == 2)
  {
    my $VMSelected = !1;
    my $VMs = CreateVMs();
    if (! $self->{ShowAll})
    {
      $VMs->AddFilter("BaseOS", [1]);
    }
    foreach my $VMKey (@{$VMs->GetKeys()})
    {
      my $VM = $VMs->GetItem($VMKey);
      my $FieldName = "vm_" . $self->CGI->escapeHTML($VM->GetKey());
      if ($self->GetParam($FieldName))
      {
        $VMSelected = 1;
        last;
      }
    }

    if (! $VMSelected)
    {
      $self->{ErrMessage} = "Select at least one VM";
      return !1;
    }
  }

  return $self->SUPER::Validate(@_);
}

sub OnNext
{
  my $self = shift;

  my $FileName = $self->GetParam("File");
  if (! $FileName)
  {
    $self->{ErrField} = "File";
    $self->{ErrMessage} = "File: Must be entered";
    return !1;
  }
  my $Fh = $self->CGI->upload("File");
  if (defined($Fh))
  {
    if ($FileName =~ /(\\|\/)/)
    {
      $FileName =~ m/^.*(\\|\/)(.*)/;
      $FileName = $2;
    }
    my $StagingFile = $self->GetStagingFileName($FileName);
    my $OldUMask = umask(002);
    if (! open (OUTFILE,">$StagingFile"))
    {
      umask($OldUMask);
      $self->{ErrField} = "File";
      $self->{ErrMessage} = "Unable to process uploaded file";
      return !1;
    }
    umask($OldUMask);
    my $Buffer;
    while (sysread($Fh, $Buffer, 4096))
    {
      print OUTFILE $Buffer;
    }
    close OUTFILE;

    $self->{FileName} = $FileName;
    $self->{Page} = 2;
  }
  else
  {
    $self->{ErrField} = "File";
    $self->{ErrMessage} = "File upload failed";
    return !1;
  }

  if (! $self->Validate)
  {
    return !1;
  }

  return 1;
}

sub OnPrev
{
  my $self = shift;

  my $StagingFileName = $self->GetStagingFileName($self->GetParam("FileName"));
  if ($StagingFileName)
  {
    unlink($StagingFileName);
  }

  $self->{Page} = 1;

  return 1;
}

sub OnSubmit
{
  my $self = shift;

  if (! $self->Validate())
  {
    return !1;
  }

  # Make sure the file has a unique name even when not picked up directly
  # by the engine
  my $FileNameRandomPart = $self->GetCurrentSession()->Id;
  while (-e ("$DataDir/staging/${FileNameRandomPart}_" .
             $self->GetParam("FileName")))
  {
    $FileNameRandomPart = GenerateRandomString(32);
  }
  if (! rename("$DataDir/staging/" . $self->GetCurrentSession()->Id . "_" .
               $self->GetParam("FileName"),
               "$DataDir/staging/${FileNameRandomPart}_" .
               $self->GetParam("FileName")))
  {
    # Can't give the file a unique name. Maybe we're lucky and using the
    # session id works
    $FileNameRandomPart = $self->GetCurrentSession()->Id;
  }

  # First create a new job
  my $Jobs = CreateJobs();
  my $NewJob = $Jobs->Add();
  $NewJob->User($self->GetCurrentSession()->User);
  $NewJob->Priority(5);
  $NewJob->Remarks($self->GetParam("Remarks"));
  
  # Add a step to the job
  my $Steps = $NewJob->Steps;
  my $NewStep = $Steps->Add();
  $NewStep->FileName($FileNameRandomPart . " " . $self->GetParam("FileName"));
  $NewStep->InStaging(1);
  
  # Add a task for each selected VM
  my $Tasks = $NewStep->Tasks;
  my $VMs = CreateVMs();
  if (! $self->{ShowAll})
  {
    $VMs->AddFilter("BaseOS", [1]);
  }
  my $SortedKeys = $VMs->SortKeysBySortOrder($VMs->GetKeys());
  foreach my $VMKey (@$SortedKeys)
  {
    my $VM = $VMs->GetItem($VMKey);
    my $FieldName = "vm_" . $self->CGI->escapeHTML($VM->GetKey());
    if ($self->GetParam($FieldName))
    {
      my $Task = $Tasks->Add();
      $Task->VM($VM);
      $Task->Type("single");
      $Task->Timeout($SingleTimeout);
      $Task->CmdLineArg($self->GetParam("CmdLineArg"));
    }
  }

  # Now save the whole thing
  my ($ErrKey, $ErrProperty, $ErrMessage) = $Jobs->Save();
  if (defined($ErrMessage))
  {
    $self->{ErrMessage} = $ErrMessage;
    return !1;
  }

  # Clean up, but save the key of the new job
  my $JobKey = $NewJob->GetKey();
  $Jobs = undef;

  # Notify engine
  if (defined(JobSubmit($JobKey)))
  {
    $self->{Page} = 3;
    $self->{JobKey} = $NewJob->GetKey();
    return !1;
  }

  $self->Redirect("/JobDetails.pl?Key=" . $NewJob->Id);
  exit;
}

sub OnShowAllVMs
{
  my $self = shift;

  $self->{ShowAll} = 1;

  return !1;
}

sub OnShowBaseVMs
{
  my $self = shift;

  $self->{ShowAll} = !1;

  return !1;
}

sub OnOK
{
  my $self = shift;

  if (defined($self->GetParam("JobKey")))
  {
    $self->Redirect("/JobDetails.pl?Key=" . $self->GetParam("JobKey"));
  }
  else
  {
    $self->Redirect("/index.pl");
  }
}

sub OnAction
{
  my $self = shift;
  my $Action = $_[0];

  if ($Action eq "Next >")
  {
    return $self->OnNext();
  }
  elsif ($Action eq "< Prev")
  {
    return $self->OnPrev();
  }
  elsif ($Action eq "Submit")
  {
    return $self->OnSubmit();
  }
  elsif ($Action eq "Show base VMs")
  {
    return $self->OnShowBaseVMs();
  }
  elsif ($Action eq "Show all VMs")
  {
    return $self->OnShowAllVMs();
  }
  elsif ($Action eq "OK")
  {
    return $self->OnOK();
  }

  return $self->SUPER::OnAction(@_);
}

package main;

my $Request = shift;

my $SubmitPage1 = SubmitPage1->new($Request, "wine-devel");
$SubmitPage1->GeneratePage();
