# Patch collection and items
#
# Copyright 2010 Ge van Geldorp
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

=head1 NAME

WineTestBot::Patches - Patch collection

=cut


package WineTestBot::Patch;

use Encode qw/decode/;
use ObjectModel::Item;
use WineTestBot::Config;
use WineTestBot::PendingPatchSeries;
use WineTestBot::Jobs;
use WineTestBot::Users;
use WineTestBot::Utils;
use WineTestBot::VMs;
use WineTestBot::Engine::Notify;

use vars qw(@ISA @EXPORT);

require Exporter;
@ISA = qw(ObjectModel::Item Exporter);

sub InitializeNew
{
  my $self = shift;

  $self->Received(time());

  $self->SUPER::InitializeNew();
}

sub FromSubmission
{
  my $self = shift;
  my $MsgEntity = $_[0];

  my $Head = $MsgEntity->head;
  my @From = Mail::Address->parse($Head->get("From"));
  if (defined($From[0]))
  {
    my $FromName = $From[0]->name;
    if (! $FromName && substr($From[0]->phrase, 0, 2) eq "=?")
    {
      $FromName = decode('MIME-Header', $From[0]->phrase);
    }
    if (! $FromName)
    {
      $FromName = $From[0]->user;
    }
    my $PropertyDescriptor = $self->GetPropertyDescriptorByName("FromName");
    $self->FromName(substr($FromName, 0, $PropertyDescriptor->GetMaxLength()));
    my $FromEMail = $From[0]->address;
    $PropertyDescriptor = $self->GetPropertyDescriptorByName("FromEMail");
    if (length($FromEMail) <= $PropertyDescriptor->GetMaxLength())
    {
      $self->FromEMail($FromEMail);
    }
  }
  my $Subject = $Head->get("Subject");
  $Subject =~ s/\s*\n\s*/ /gs;
  my $PropertyDescriptor = $self->GetPropertyDescriptorByName("Subject");
  $self->Subject(substr($Subject, 0, $PropertyDescriptor->GetMaxLength()));

  $self->Disposition("Processing");
}

sub Submit
{
  my $self = shift;
  my ($PatchFileName, $IsSeries) = @_;

  my %Targets;
  if (open(BODY, "<$PatchFileName"))
  {
    my $Line;
    while (defined($Line = <BODY>))
    {
      if ($Line =~ m/^\+\+\+ .*\/([^\/]+)\/tests\/([^\/]+)\.c/)
      {
        $Targets{"$1/$2"} = 1;
      }
    }
    close BODY;
  }

  if (! scalar(%Targets))
  {
    $self->Disposition(($IsSeries ? "Series" : "Patch") .
                       " doesn't affect tests");
    return undef;
  }

  # Create a link to the patch file in the staging dir
  my $FileNameRandomPart = GenerateRandomString(32);
  while (-e ("$DataDir/staging/${FileNameRandomPart}_patch"))
  {
    $FileNameRandomPart = GenerateRandomString(32);
  }
  link $PatchFileName, "$DataDir/staging/${FileNameRandomPart}_patch";

  my $User;
  my $Users = CreateUsers();
  if (defined($self->FromEMail))
  {
    $Users->AddFilter("EMail", [$self->FromEMail]);
    if (! $Users->IsEmpty())
    {
      $User = $Users->GetItem(@{$Users->GetKeys()}[0]);
    }
  }
  if (! defined($User))
  {
    $User = $Users->GetBatchUser();
  }

  my $Jobs = WineTestBot::Jobs::CreateJobs();

  foreach my $Target (keys %Targets)
  {
    $Target =~ m/^([^\/]+)\/([^\/]+)$/;
    my $DllBaseName = $1;
    my $TestSet = $2;

    # Create a new job for this patch
    my $NewJob = $Jobs->Add();
    $NewJob->User($User);
    $NewJob->Priority(9);
    my $PropertyDescriptor = $Jobs->GetPropertyDescriptorByName("Remarks");
    my $Subject = $self->Subject;
    $Subject =~ s/\[PATCH[^\]]*]//i;
    $Subject =~ s/[[\(]?\d+\/\d+[\)\]]?//;
    $Subject =~ s/^\s*//;
    $NewJob->Remarks(substr("[wine-patches] " . $Subject, 0,
                            $PropertyDescriptor->GetMaxLength()));
    $NewJob->Patch($self);
  
    # Add build step to the job
    my $Steps = $NewJob->Steps;
    my $NewStep = $Steps->Add();
    $NewStep->FileName($FileNameRandomPart . " patch");
    $NewStep->InStaging(1);
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
  
    # Add 32-bit test run
    $NewStep = $Steps->Add();
    $NewStep->FileName("${DllBaseName}_test.exe");
    $NewStep->InStaging(!1);
  
    # Add 32-bit tasks
    $Tasks = $NewStep->Tasks;
    $VMs = CreateVMs();
    $VMs->AddFilter("Type", ["base"]);
    my $Have64VMs = !1;
    my $SortedKeys = $VMs->SortKeysBySortOrder($VMs->GetKeys());
    foreach my $VMKey (@$SortedKeys)
    {
      my $VM = $VMs->GetItem($VMKey);
      my $Task = $Tasks->Add();
      $Task->VM($VM);
      $Task->Timeout($SingleTimeout);
      $Task->CmdLineArg($TestSet);
      if ($VM->Bits == 64)
      {
        $Have64VMs = 1;
      }
    }
  
    if ($Have64VMs)
    {
      # Add 64-bit test run
      $NewStep = $Steps->Add();
      $NewStep->FileName("${DllBaseName}_test64.exe");
      $NewStep->InStaging(!1);
    
      # Add 64-bit tasks
      $Tasks = $NewStep->Tasks;
      foreach my $VMKey (@$SortedKeys)
      {
        my $VM = $VMs->GetItem($VMKey);
        if ($VM->Bits == 64)
        {
          my $Task = $Tasks->Add();
          $Task->VM($VM);
          $Task->Timeout($SingleTimeout);
          $Task->CmdLineArg($TestSet);
        }
      }
    }
  }

  my ($ErrKey, $ErrProperty, $ErrMessage) = $Jobs->Save();
  if (defined($ErrMessage))
  {
    $self->Disposition("Failed to submit job");
    return $ErrMessage;
  }
  $Jobs->Schedule();

  my $Disposition = "Submitted job ";
  my $First = 1;
  my @SortedKeys = sort @{$Jobs->GetKeys()};
  foreach my $JobKey (@SortedKeys)
  {
    if ($First)
    {
      $First = !1;
    }
    else
    {
      $Disposition .= ", ";
    }
    $Disposition .= $JobKey;
  }
  $self->Disposition($Disposition);

  return undef;
}

sub GetEMailRecipient
{
  my $self = shift;

  return BuildEMailRecipient($self->FromEMail, $self->FromName);
}

package WineTestBot::Patches;

use ObjectModel::BasicPropertyDescriptor;
use ObjectModel::Collection;
use ObjectModel::PropertyDescriptor;
use WineTestBot::Config;

use vars qw(@ISA @EXPORT);

require Exporter;
@ISA = qw(ObjectModel::Collection Exporter);
@EXPORT = qw(&CreatePatches);

my @PropertyDescriptors;

BEGIN
{
  $PropertyDescriptors[0] =
    CreateBasicPropertyDescriptor("Id", "Patch id", 1, 1, "S",  7);
  $PropertyDescriptors[1] =
    CreateBasicPropertyDescriptor("Received", "Received", !1, 1, "DT", 19);
  $PropertyDescriptors[2] =
    CreateBasicPropertyDescriptor("FromName", "Author", !1, !1, "A", 40);
  $PropertyDescriptors[3] =
    CreateBasicPropertyDescriptor("FromEMail", "Email address author", !1, !1, "A", 40);
  $PropertyDescriptors[4] =
    CreateBasicPropertyDescriptor("Subject", "Subject", !1, !1, "A", 120);
  $PropertyDescriptors[5] =
    CreateBasicPropertyDescriptor("Disposition", "Disposition", !1, 1, "A", 40);
}

sub CreateItem
{
  my $self = shift;

  return WineTestBot::Patch->new($self);
}

sub IsPatch
{
  my $self = shift;
  my $Body = $_[0];

  if (open(BODY, "<" . $Body->path))
  {
    my $Line;
    while (defined($Line = <BODY>))
    {
      if ($Line =~ m/^\+\+\+ / || $Line =~ m/^diff/)
      {
        close BODY;
        return 1;
      }
    }
    close BODY;
  }

  return !1;
}

sub NewSubmission
{
  my $self = shift;
  my $MsgEntity = $_[0];

  my $Patch = $self->Add();
  $Patch->FromSubmission($MsgEntity);

  my @PatchBodies;
  foreach my $Part ($MsgEntity->parts_DFS)
  {
    if (defined($Part->bodyhandle))
    {
      if ($Part->effective_type ne "text/html" &&
          $self->IsPatch($Part->bodyhandle))
      {
        $PatchBodies[scalar(@PatchBodies)] = $Part->bodyhandle;
      }
      else
      {
        $Part->bodyhandle->purge();
      }
    }
  }

  my $ErrMessage;
  if (scalar(@PatchBodies) == 1)
  {
    if ($Patch->Subject =~ m/\d+\/\d+/)
    {
      $Patch->Disposition("Checking series");
      my $ErrKey;
      my $ErrProperty;
      ($ErrKey, $ErrProperty, $ErrMessage) = $self->Save();
      link($PatchBodies[0]->path, "$DataDir/patches/" . $Patch->Id);
      if (! defined($ErrMessage))
      {
        $ErrMessage = WineTestBot::PendingPatchSeriesCollection::CreatePendingPatchSeriesCollection()->NewSubmission($Patch);
      }
    }
    else
    {
      $Patch->Disposition("Checking patch");
      my $ErrKey;
      my $ErrProperty;
      ($ErrKey, $ErrProperty, $ErrMessage) = $self->Save();
      link($PatchBodies[0]->path, "$DataDir/patches/" . $Patch->Id);
      if (! defined($ErrMessage))
      {
        $ErrMessage = $Patch->Submit($PatchBodies[0]->path, !1);
      }
    }
  }
  elsif (scalar(@PatchBodies) == 0)
  {
    $Patch->Disposition("No patch found");
  }
  else
  {
    $Patch->Disposition("Message contains multiple patches");
  }

  foreach my $PatchBody (@PatchBodies)
  {
    $PatchBody->purge();
  }
  
  if (! defined($ErrMessage))
  {
    my ($ErrKey, $ErrProperty, $ErrMessage) = $self->Save();
    if (defined($ErrMessage))
    {
      return $ErrMessage;
    }
  }

  return undef;
}

sub CreatePatches
{
  return WineTestBot::Patches->new("Patches", "Patches", "Patch", \@PropertyDescriptors);
}

1;
