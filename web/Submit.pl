# WineTestBot job submit page
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

package SubmitPage;

use CGI qw(:standard);
use Fcntl;
use IO::Handle;
use POSIX qw(:fcntl_h);
use ObjectModel::BasicPropertyDescriptor;
use ObjectModel::CGI::FreeFormPage;
use WineTestBot::Config;
use WineTestBot::Jobs;
use WineTestBot::Engine::Notify;
use WineTestBot::Utils;
use WineTestBot::VMs;

@SubmitPage::ISA = qw(ObjectModel::CGI::FreeFormPage);

sub _initialize
{
  my $self = shift;

  $self->{Page} = $self->GetParam("Page") || 1;

  my @PropertyDescriptors1;
  $PropertyDescriptors1[0] = CreateBasicPropertyDescriptor("Remarks", "Remarks", !1, !1, "A", 50);
  $self->{PropertyDescriptors1} = \@PropertyDescriptors1;

  my @PropertyDescriptors3;
  $PropertyDescriptors3[0] = CreateBasicPropertyDescriptor("TestExecutable", "Test executable", !1, 1, "A", 50);
  $PropertyDescriptors3[1] = CreateBasicPropertyDescriptor("CmdLineArg", "Command line arguments", !1, !1, "A", 50);
  $PropertyDescriptors3[2] = CreateBasicPropertyDescriptor("Run64", "Run 64-bit tests in addition to 32-bit tests", !1, 1, "B", 1);
  $PropertyDescriptors3[3] = CreateBasicPropertyDescriptor("DebugLevel", "Debug level (WINETEST_DEBUG)", !1, 1, "N", 2);
  $PropertyDescriptors3[4] = CreateBasicPropertyDescriptor("ReportSuccessfulTests", "Report successfull tests (WINETEST_REPORT_SUCCESS)", !1, 1, "B", 1);
  $self->{PropertyDescriptors3} = \@PropertyDescriptors3;

  if ($self->{Page} == 2)
  {
    $self->{ShowAll} = defined($self->GetParam("ShowAll"));
  }

  $self->SUPER::_initialize(undef);
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
    return "Specify the patch file that you want to upload and submit " .
           "for testing.<br>\n" .
           "You can also specify a Windows .exe file, this would normally be " .
           "a Wine test executable that you cross-compiled."
  }
  elsif ($self->{Page} == 2)
  {
    return "Select the VMs on which you want to run your test";
  }
  elsif ($self->{Page} == 4)
  {
    return "Your job was successfully queued, but the job engine that takes " .
           "care of actually running it seems to be unavailable (perhaps it " .
           "crashed). Your job will remain queued until the engine is " .
           "restarted.";
  }

  return "";
}

sub GetPropertyDescriptors
{
  my $self = shift;

  if ($self->{Page} == 1)
  {
    return $self->{PropertyDescriptors1};
  }
  elsif ($self->{Page} == 3)
  {
    return $self->{PropertyDescriptors3};
  }

  return $self->SUPER::GetPropertyDescriptors(@_);
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
  else
  {
    if (! defined($self->{FileName}))
    {
      $self->{FileName} = $self->GetParam("FileName");
    }
    if (! defined($self->{FileType}))
    {
      $self->{FileType} = $self->GetParam("FileType");
    }
    if (! defined($self->{TestExecutable}))
    {
      $self->{TestExecutable} = $self->GetParam("TestExecutable");
    }
    if (! defined($self->{CmdLineArg}))
    {
      $self->{CmdLineArg} = $self->GetParam("CmdLineArg");
    }
    print "<div><input type='hidden' name='Remarks' value='",
          $self->CGI->escapeHTML($self->GetParam("Remarks")), "'></div>\n";
    print "<div><input type='hidden' name='FileName' value='",
          $self->CGI->escapeHTML($self->{FileName}), "'></div>\n";
    print "<div><input type='hidden' name='FileType' value='",
          $self->CGI->escapeHTML($self->{FileType}), "'></div>\n";
    if ($self->{Page} != 3)
    {
      if (defined($self->{TestExecutable}))
      {
        print "<div><input type='hidden' name='TestExecutable' value='",
              $self->CGI->escapeHTML($self->{TestExecutable}), "'></div>\n";
      }
      if (defined($self->{CmdLineArg}))
      {
        print "<div><input type='hidden' name='CmdLineArg' value='",
              $self->CGI->escapeHTML($self->{CmdLineArg}), "'></div>\n";
      }
    }
    if ($self->{Page} == 2)
    {
      if ($self->GetParam("Page") == 3)
      {
        my $VMs = CreateVMs();
        foreach my $VMKey (@{$VMs->GetKeys()})
        {
          my $VM = $VMs->GetItem($VMKey);
          my $FieldName = "vm_" . $self->CGI->escapeHTML($VMKey);
          if (defined($self->GetParam($FieldName)) && $VM->Type ne "base")
          {
            $self->{ShowAll} = 1;
            last;
          }
        }
      }
      if ($self->{ShowAll})
      {
        print "<div><input type='hidden' name='ShowAll' value='1'></div>\n";
      }
  
      my $VMs = CreateVMs();
      if ($self->{ShowAll})
      {
        $VMs->AddFilter("Type", ["base", "extra"]);
      }
      else
      {
        $VMs->AddFilter("Type", ["base"]);
      }
      my $SortedKeys = $VMs->SortKeysBySortOrder($VMs->GetKeys());
      foreach my $VMKey (@$SortedKeys)
      {
        my $VM = $VMs->GetItem($VMKey);
        if ($VM->Bits == 64 || $self->{FileType} eq "pe32" ||
            $self->{FileType} eq "patch")
        {
          my $FieldName = "vm_" . $self->CGI->escapeHTML($VM->GetKey());
          print "<div class='ItemProperty'><label>",
                $self->CGI->escapeHTML($VM->Name);
          if ($VM->Description)
          {
            print " (", $self->CGI->escapeHTML($VM->Description), ")";
          }
          print "</label><div class='ItemValue'><input type='checkbox' name='$FieldName'";
          if ($self->GetParam("Page") == 1 || $self->GetParam($FieldName))
          {
            print " checked='checked'";
          }
          print "/></div></div>\n";
        }
      }
    }
    else
    {
      if (defined($self->{NoCmdLineArgWarn}))
      {
        print "<div><input type='hidden' name='NoCmdLineArgWarn' value='on'>",
              "</div>\n";
      }
      my $VMs = CreateVMs();
      foreach my $VMKey (@{$VMs->GetKeys()})
      {
        my $VM = $VMs->GetItem($VMKey);
        my $FieldName = "vm_" . $self->CGI->escapeHTML($VM->GetKey());
        if ($self->GetParam($FieldName))
        {
          print "<div><input type='hidden' name='$FieldName' value='on'>",
                "</div>\n";
        }
      }
    }
  }
  if ($self->{Page} == 4)
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
    push(@$Actions, "< Prev", "Next >");
  }
  elsif ($self->{Page} == 3)
  {
    push(@$Actions, "< Prev", "Submit");
  }
  elsif ($self->{Page} == 4)
  {
    push(@$Actions, "OK");
  }

  return $Actions;
}

sub DisplayProperty
{
  my $self = shift;
  my $PropertyDescriptor = $_[0];

  if ($self->{Page} == 3)
  {
    my $PropertyName = $PropertyDescriptor->GetName();
    if ($self->GetParam("FileType") eq "patch")
    {
      if ($PropertyName eq "Run64")
      {
        my $Show64 = !1;
        my $VMs = CreateVMs();
        foreach my $VMKey (@{$VMs->GetKeys()})
        {
          my $VM = $VMs->GetItem($VMKey);
          my $FieldName = "vm_" . $self->CGI->escapeHTML($VM->GetKey());
          if ($self->GetParam($FieldName) && $VM->Bits == 64)
          {
            $Show64 = 1;
            last;
          }
        }
        if (! $Show64)
        {
          return "";
        }
      }
    }
    else
    {
      if ($PropertyName eq "TestExecutable" || $PropertyName eq "Run64")
      {
        return "";
      }
    }
  }

  return $self->SUPER::DisplayProperty(@_);
}

sub GetPropertyValue
{
  my $self = shift;
  my $PropertyDescriptor = $_[0];

  if ($self->{Page} == 3)
  {
    my $PropertyName = $PropertyDescriptor->GetName();
    if ($PropertyName eq "DebugLevel")
    {
      return 1;
    }
    if ($PropertyName eq "Run64")
    {
      return 1;
    }
  }

  return $self->SUPER::GetPropertyValue(@_);
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
    if ($self->{ShowAll})
    {
      $VMs->AddFilter("Type", ["base", "extra"]);
    }
    {
      $VMs->AddFilter("Type", ["base"]);
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
  elsif ($self->{Page} == 3 && $self->GetParam("Page") == 3)
  {
    if ($self->GetParam("FileType") eq "patch" &&
        ! ($self->GetParam("TestExecutable") =~ m/^[a-zA-Z0-9_]+_test\.exe/))
    {
      $self->{ErrMessage} = "Invalid name for Test executable";
      $self->{ErrField} = "TestExecutable";
      return !1;
    }

    if ($self->GetParam("NoCmdLineArgWarn"))
    {
      $self->{NoCmdLineArgWarn} = 1;
    }
    elsif (! $self->GetParam("CmdLineArg"))
    {
      $self->{ErrMessage} = "You didn't specify a command line argument. " .
                            "This is most likely not correct, so please " .
                            "fix this. If you're sure that you really don't " .
                            'want a command line argument, press "Submit" ' .
                            "again.";
      $self->{ErrField} = "CmdLineArg";
      $self->{NoCmdLineArgWarn} = 1;
      return !1;
    }
  }

  return $self->SUPER::Validate(@_);
}

sub DetermineFileType
{
  my $self = shift;
  my $FileName = $_[0];

  my $ErrMessage = undef;
  my $FileType = "unknown";
  my $DllBaseName = undef;
  my $TestSet = undef;
  if (! sysopen(FH, $FileName, O_RDONLY))
  {
    return ("Unable to open $FileName", "unknown", undef, undef);
  }

  my $Buffer;
  if (sysread(FH, $Buffer, 0x40))
  {
    # Unpack IMAGE_DOS_HEADER
    my @Fields = unpack "S30I", $Buffer;
    if ($Fields[0] == 0x5a4d)
    {
      seek FH, $Fields[30], SEEK_SET;
      if (sysread(FH, $Buffer, 0x06))
      {
        @Fields = unpack "IS", $Buffer;
        if ($Fields[0] == 0x00004550 && $Fields[1] == 0x014c)
        {
          $FileType = "pe32";
        }
        elsif ($Fields[0] == 0x00004550 && $Fields[1] == 0x8664)
        {
          $FileType = "pe64";
        }
      }
    }
  }

  close FH;

  if ($FileType eq "unknown")
  {
    if (open (FH, "<$FileName"))
    {
      my $Line;
      while (defined($Line = <FH>))
      {
        if ($Line =~ m/^diff/)
        {
          $FileType = "patch";
        }
        elsif ($Line =~ m/^\+\+\+ .*\/([^\/]+)\/tests\/([^\/]+)\.c/)
        {
          $FileType = "patch";
          if (defined($DllBaseName) || defined($TestSet))
          {
            $ErrMessage = "Patch contains changes to multiple tests";
          }
          else
          {
            $DllBaseName = $1;
            $TestSet = $2;
          }
        }
      }
      close FH;
    }
  }

  return ($ErrMessage, $FileType, $DllBaseName, $TestSet);
}

sub OnPage1Next
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

    my ($ErrMessage, $FileType, $DllBaseName, $TestSet) = $self->DetermineFileType($StagingFile);
    if (defined($ErrMessage))
    {
      $self->{ErrField} = "File";
      $self->{ErrMessage} = $ErrMessage;
      return !1;
    }
    if ($FileType ne "patch" && $FileType ne "pe32" && $FileType ne "pe64")
    {
      $self->{ErrField} = "File";
      $self->{ErrMessage} = "Unrecognized file type, it's not a patch or PE file";
      return !1;
    }

    $self->{FileName} = $FileName;
    $self->{FileType} = $FileType;
    if (defined($DllBaseName))
    {
      $self->{TestExecutable} = $DllBaseName . "_test.exe";
    }
    if (defined($TestSet))
    {
      $self->{CmdLineArg} = $TestSet;
    }
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

  $self->{Page} = 2;

  return 1;
}

sub OnPage2Next
{
  my $self = shift;

  if (! $self->Validate)
  {
    return !1;
  }

  $self->{Page} = 3;

  return 1;
}

sub OnNext
{
  my $self = shift;

  return $self->{Page} == 2 ? $self->OnPage2Next() : $self->OnPage1Next();
}

sub OnPage2Prev
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

sub OnPage3Prev
{
  my $self = shift;

  $self->{Page} = 2;

  return 1;
}

sub OnPrev
{
  my $self = shift;

  return $self->{Page} == 3 ? $self->OnPage3Prev() : $self->OnPage2Prev();
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
  if ($self->GetParam("FileType") eq "patch")
  {
    $NewStep->Type("build");
    $NewStep->DebugLevel(0);

    # Add build task
    my $Tasks = $NewStep->Tasks;
    my $VMs = CreateVMs();
    $VMs->AddFilter("Type", ["build"]);
    my $BuildKey = ${$VMs->GetKeys()}[0];
    my $VM = $VMs->GetItem($BuildKey);
    my $Task = $Tasks->Add();
    $Task->VM($VM);
    $Task->Timeout($BuildTimeout);

    # Add test run step
    $NewStep = $Steps->Add();
    $NewStep->FileName($self->GetParam("TestExecutable"));
    $NewStep->InStaging(!1);
  }

  $NewStep->Type("single");
  $NewStep->DebugLevel($self->GetParam("DebugLevel"));
  $NewStep->ReportSuccessfulTests(defined($self->GetParam("ReportSuccessfulTests")));
  
  # Add a task for each selected VM
  my $Tasks = $NewStep->Tasks;
  my $VMs = CreateVMs();
  my $SortedKeys = $VMs->SortKeysBySortOrder($VMs->GetKeys());
  foreach my $VMKey (@$SortedKeys)
  {
    my $VM = $VMs->GetItem($VMKey);
    my $FieldName = "vm_" . $self->CGI->escapeHTML($VM->GetKey());
    if ($self->GetParam($FieldName))
    {
      my $Task = $Tasks->Add();
      $Task->VM($VM);
      $Task->Timeout($SingleTimeout);
      $Task->CmdLineArg($self->GetParam("CmdLineArg"));
    }
  }

  if ($self->GetParam("FileType") eq "patch" &&
      defined($self->GetParam("Run64")))
  {
    # Add step and tasks for 64-bit exe
    $NewStep = $Steps->Add();
    my $FileName64 = $self->GetParam("TestExecutable");
    $FileName64 =~ s/^([a-zA-Z0-9_]+)_test\.exe/\1_test64.exe/;
    $NewStep->FileName($FileName64);
    $NewStep->InStaging(!1);
    $NewStep->Type("single");
    $NewStep->DebugLevel($self->GetParam("DebugLevel"));
    $NewStep->ReportSuccessfulTests(defined($self->GetParam("ReportSuccessfulTests")));
  
    # Add a task for each selected 64-bit VM
    my $Tasks = $NewStep->Tasks;
    my $VMs = CreateVMs();
    my $SortedKeys = $VMs->SortKeysBySortOrder($VMs->GetKeys());
    foreach my $VMKey (@$SortedKeys)
    {
      my $VM = $VMs->GetItem($VMKey);
      my $FieldName = "vm_" . $self->CGI->escapeHTML($VM->GetKey());
      if ($VM->Bits == 64 && $self->GetParam($FieldName))
      {
        my $Task = $Tasks->Add();
        $Task->VM($VM);
        $Task->Timeout($SingleTimeout);
        $Task->CmdLineArg($self->GetParam("CmdLineArg"));
      }
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
    $self->{Page} = 4;
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

my $SubmitPage = SubmitPage->new($Request, "wine-devel");
$SubmitPage->GeneratePage();
