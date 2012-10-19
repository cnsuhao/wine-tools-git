# Copyright 2009 Ge van Geldorp
# Copyright 2012 Francois Gouget
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


package WineTestBot::Job;

=head1 NAME

WineTestBot::Job - A job submitted by a user

=head1 DESCRIPTION

A Job is created when a WineTestBot::User asks for something to be tested
(for automatically generated Jobs this would be the batch user). There are many
paths that can result in the creation of a job:

=over

=item *
A use submits a patch or binary to test.

=item *
WineTestBot finds a patch to test on the mailing list (and has all the pieces
it needs for that patch, see WineTestBot::PendingPatchSet).

=item *
WineTestBot notices a Wine commit round and decides to run the full suite of
tests. In this case there is no WineTestBot::Patch object associated with the
Job.

=back

A Job is composed of multiple WineTestBot::Step objects.

=cut

use WineTestBot::Branches;
use WineTestBot::Engine::Notify;
use WineTestBot::WineTestBotObjects;

use vars qw(@ISA @EXPORT);

require Exporter;
@ISA = qw(WineTestBot::WineTestBotItem Exporter);

sub _initialize
{
  my $self = shift;

  $self->SUPER::_initialize(@_);

  $self->{OldStatus} = undef;
}

sub InitializeNew
{
  my $self = shift;

  $self->Archived(!1);
  $self->Branch(CreateBranches()->GetDefaultBranch());
  $self->Status("queued");
  $self->Submitted(time());

  $self->SUPER::InitializeNew();
}

sub Status
{
  my $self = shift;

  my $CurrentStatus = $self->SUPER::Status;
  if (! @_)
  {
    return $CurrentStatus;
  }

  my $NewStatus = $_[0];
  if (! defined($CurrentStatus) || $NewStatus ne $CurrentStatus)
  {
    $self->SUPER::Status($NewStatus);
    $self->{OldStatus} = $CurrentStatus;
  }

  return $NewStatus;
}

sub OnSaved
{
  my $self = shift;

  $self->SUPER::OnSaved(@_);

  if (defined($self->{OldStatus}))
  {
    my $NewStatus = $self->Status;
    if ($NewStatus ne $self->{OldStatus})
    {
      JobStatusChange($self->GetKey(), $self->{OldStatus}, $NewStatus);
    }
  }
}

sub UpdateStatus
{
  my $self = shift;

  my $Steps = $self->Steps;
  my $HasQueuedStep = !1;
  my $HasRunningStep = !1;
  my $HasCompletedStep = !1;
  my $HasFailedStep = !1;
  my @SortedSteps = sort { $a->No <=> $b->No } @{$Steps->GetItems()};
  foreach my $Step (@SortedSteps)
  {
    my $Status = $Step->Status;
    if ($Status eq "queued" || $Status eq "running")
    {
      my $Tasks = $Step->Tasks;
      my $HasQueuedTask = !1;
      my $HasRunningTask = !1;
      my $HasCompletedTask = !1;
      my $HasFailedTask = !1;
      foreach my $TaskKey (@{$Tasks->GetKeys()})
      {
        my $Task = $Tasks->GetItem($TaskKey);
        $Status = $Task->Status;
        if ($HasFailedStep && $Status eq "queued")
        {
          $Status = "skipped";
          $Task->Status("skipped");
        }
        $HasQueuedTask = $HasQueuedTask || $Status eq "queued";
        $HasRunningTask = $HasRunningTask || $Status eq "running";
        $HasCompletedTask = $HasCompletedTask || $Status eq "completed";
        $HasFailedTask = $HasFailedTask || $Status eq "failed";
      }
      if ($HasFailedStep)
      {
        $Step->Status("skipped");
      }
      elsif ($HasRunningTask || ($HasQueuedTask && ($HasCompletedTask ||
                                                    $HasFailedTask)))
      {
        $Step->Status("running");
      }
      elsif ($HasFailedTask)
      {
        $Step->Status("failed");
      }
      elsif ($HasCompletedTask || ! $HasQueuedTask)
      {
        $Step->Status("completed");
      }
      else
      {
        $Step->Status("queued");
      }
      $Step->Save();
    }

    $Status = $Step->Status;
    $HasQueuedStep = $HasQueuedStep || $Status eq "queued";
    $HasRunningStep = $HasRunningStep || $Status eq "running";
    $HasCompletedStep = $HasCompletedStep || $Status eq "completed";
    my $Type = $Step->Type;
    $HasFailedStep = $HasFailedStep ||
                     ($Status eq "failed" &&
                      ($Type eq "build" || $Type eq "reconfig"));
  }

  if ($HasRunningStep || ($HasQueuedStep && ($HasCompletedStep ||
                                             $HasFailedStep)))
  {
    $self->Status("running");
  }
  elsif ($HasFailedStep)
  {
    if (! defined($self->Ended))
    {
      $self->Ended(time);
    }
    $self->Status("failed");
  }
  elsif ($HasCompletedStep || ! $HasQueuedStep)
  {
    if (! defined($self->Ended))
    {
      $self->Ended(time);
    }
    $self->Status("completed");
  }
  else
  {
    $self->Status("queued");
  }
  $self->Save();
}

sub Cancel
{
  my $self = shift;

  my $Steps = $self->Steps;
  foreach my $StepKey (@{$Steps->GetKeys()})
  {
    my $Step = $Steps->GetItem($StepKey);
    my $Status = $Step->Status;
    if ($Status eq "queued" || $Status eq "running")
    {
      my $Tasks = $Step->Tasks;
      foreach my $TaskKey (@{$Tasks->GetKeys()})
      {
        my $Task = $Tasks->GetItem($TaskKey);
        if ($Task->Status eq "queued")
        {
          $Task->Status("skipped");
          $Task->Save();
        }
      }
    }
  }

  foreach my $StepKey (@{$Steps->GetKeys()})
  {
    my $Step = $Steps->GetItem($StepKey);
    my $Status = $Step->Status;
    if ($Status eq "queued" || $Status eq "running")
    {
      my $Tasks = $Step->Tasks;
      foreach my $TaskKey (@{$Tasks->GetKeys()})
      {
        my $Task = $Tasks->GetItem($TaskKey);
        if ($Task->Status eq "running")
        {
          if (defined($Task->ChildPid))
          {
            kill "TERM", $Task->ChildPid;
          }
        }
      }
    }
  }

  return undef;
}

sub GetEMailRecipient
{
  my $self = shift;

  if (defined($self->Patch) && defined($self->Patch->FromEMail))
  {
    return $self->Patch->FromEMail;
  }

  if ($self->User->EMail eq "/dev/null")
  {
    return undef;
  }

  return $self->User->GetEMailRecipient();
}

sub GetDescription
{
  my $self = shift;

  if (defined($self->Patch) && defined($self->Patch->FromEMail))
  {
    return $self->Patch->Subject;
  }

  return $self->Remarks;
}


package WineTestBot::Jobs;

=head1 NAME

WineTestBot::Jobs - A Job collection

=head1 DESCRIPTION

This collection contains all known jobs: those have have been run as well as
those that are yet to be run.

=cut

use POSIX qw(:errno_h);
use ObjectModel::BasicPropertyDescriptor;
use ObjectModel::EnumPropertyDescriptor;
use ObjectModel::DetailrefPropertyDescriptor;
use ObjectModel::ItemrefPropertyDescriptor;
use ObjectModel::PropertyDescriptor;
use WineTestBot::Branches;
use WineTestBot::Config;
use WineTestBot::Log;
use WineTestBot::Patches;
use WineTestBot::Steps;
use WineTestBot::Users;
use WineTestBot::VMs;
use WineTestBot::WineTestBotObjects;

use vars qw(@ISA @EXPORT @PropertyDescriptors);

require Exporter;
@ISA = qw(WineTestBot::WineTestBotCollection Exporter);
@EXPORT = qw(&CreateJobs);

my @PropertyDescriptors;

BEGIN
{
  @PropertyDescriptors = (
    CreateBasicPropertyDescriptor("Id", "Job id", 1, 1, "S",  5),
    CreateBasicPropertyDescriptor("Archived", "Job is archived", !1, 1, "B", 1),
    CreateItemrefPropertyDescriptor("Branch", "Branch", !1, 1, \&CreateBranches, ["BranchName"]),
    CreateItemrefPropertyDescriptor("User", "Author", !1, 1, \&WineTestBot::Users::CreateUsers, ["UserName"]),
    CreateBasicPropertyDescriptor("Priority", "Priority", !1, 1, "N", 1),
    CreateEnumPropertyDescriptor("Status", "Status", !1, 1, ['queued', 'running', 'completed', 'failed']),
    CreateBasicPropertyDescriptor("Remarks", "Remarks", !1, !1, "A", 50),
    CreateBasicPropertyDescriptor("Submitted", "Submitted", !1, !1, "DT", 19),
    CreateBasicPropertyDescriptor("Ended", "Ended", !1, !1, "DT", 19),
    CreateItemrefPropertyDescriptor("Patch", "Submitted from patch", !1, !1, \&WineTestBot::Patches::CreatePatches, ["PatchId"]),
    CreateDetailrefPropertyDescriptor("Steps", "Steps", !1, !1, \&CreateSteps),
  );
}

sub CreateItem
{
  my $self = shift;

  return WineTestBot::Job->new($self);
}

sub CreateJobs
{
  return WineTestBot::Jobs->new("Jobs", "Jobs", "Job", \@PropertyDescriptors);
}

sub CompareJobPriority
{
  my $Compare = $a->Priority <=> $b->Priority;
  if ($Compare == 0)
  {
    $Compare = $a->Id <=> $b->Id;
  }

  return $Compare;
}

sub CompareTaskStatus
{
  my $Compare = $b->Status cmp $a->Status;
  if ($Compare == 0)
  {
    $Compare = $a->No <=> $b->No;
  }

  return $Compare;
}

=pod
=over 12

=item C<ScheduleOnHost()>

This manages the VMs and WineTestBot::Task objects corresponding to the
hypervisors of a given host. To stay within the host's resource limits the
scheduler must take the following constraints into account:
=over

=item *

Jobs should be run in decreasing order of priority.

=item *

A Job's Steps must be run in sequential order.

=item *

A Step's tasks can be run in parallel but only one task can be running in a VM
at a given time. Also a VM must be prepared before it can run its task, see the
VM Statuses.

=item *

The number of VMs running on the host must be kept under $MaxRunningVMs. The
rational behind this limit is that the host may not be able to run more VMs
simultaneously, typically due to memory or CPU constraints. Also note that
this limit must be respected even if there are more than one hypervisor running
on the host.

=item *

FIXME: The actual limit on the number of powered on VMs is blurred by the
$MaxExtraPoweredOnVms setting and the last loop in ScheduleOnHost().

=item *

The number of VMs being reverted on the host at a given time must be kept under
$MaxRevertingVMs. This may be set to 1 in case the hypervisor gets confused
when reverting too many VMs at once.

=item *

No Task is started while there are VMs that are being reverted. This is so that
the tests are not disrupted by the disk or CPU activity caused reverting a VM.

=cut

=back
=cut

sub ScheduleOnHost
{
  my $self = shift;
  my $Hypervisors = $_[0];

  my $HostVMs = CreateVMs();
  $HostVMs->FilterHypervisor($Hypervisors);
  my ($RevertingVMs, $RunningVMs) = $HostVMs->CountRevertingRunningVMs();
  my $PoweredOnExtraVMs = $HostVMs->CountPoweredOnExtraVMs();
  my %DirtyVMsBlockingJobs;

  $self->AddFilter("Status", ["queued", "running"]);
  my @SortedJobs = sort CompareJobPriority @{$self->GetItems()};

  my $DirtyIndex = 0;
  foreach my $Job (@SortedJobs)
  {
    my $Steps = $Job->Steps;
    $Steps->AddFilter("Status", ["queued", "running"]);
    my @SortedSteps = sort { $a->No <=> $b->No } @{$Steps->GetItems()};
    if (@SortedSteps != 0)
    {
      my $Step = $SortedSteps[0];
      $Step->HandleStaging($Job->GetKey());
      my $Tasks = $Step->Tasks;
      $Tasks->AddFilter("Status", ["queued", "running"]);
      my @SortedTasks = sort CompareTaskStatus @{$Tasks->GetItems()};
      foreach my $Task (@SortedTasks)
      {
        if ($Task->Status eq "queued" &&
            $HostVMs->ItemExists($Task->VM->GetKey()))
        {
          my $VM = $HostVMs->GetItem($Task->VM->GetKey());
          if ($VM->Status eq "idle" &&
              (! defined($MaxRunningVMs) || $RunningVMs < $MaxRunningVMs) &&
              $RevertingVMs == 0)
          {
            $VM->Status("running");
            my ($ErrProperty, $ErrMessage) = $HostVMs->Save();
            if (defined($ErrMessage))
            {
              return $ErrMessage;
            }
            $ErrMessage = $Task->Run($Job->Id, $Step->No);
            if (defined($ErrMessage))
            {
              return $ErrMessage;
            }
            $Job->UpdateStatus;
            $RunningVMs++;
          }
          elsif ($VM->Status eq "dirty")
          {
            my $VMKey = $VM->GetKey();
            if (! defined($DirtyVMsBlockingJobs{$VMKey}) ||
                $Job->Priority < $DirtyVMsBlockingJobs{$VMKey})
            {
              $DirtyVMsBlockingJobs{$VMKey} = $DirtyIndex;
              $DirtyIndex++;
            }
          }
        }
      }
    }
  }

  if ($RunningVMs != 0)
  {
    return undef;
  }

  # Sort the VMs by decreasing order of priority of their Jobs
  my @DirtyVMsByIndex = sort { $DirtyVMsBlockingJobs{$a} <=> $DirtyVMsBlockingJobs{$b} } keys %DirtyVMsBlockingJobs;
  my $VMKey;
  foreach $VMKey (@DirtyVMsByIndex)
  {
    my $VM = $HostVMs->GetItem($VMKey);
    if (! defined($MaxRevertingVMs) || $RevertingVMs < $MaxRevertingVMs)
    {
      if ($VM->Type eq "extra" || $VM->Type eq "retired")
      {
        if (! defined($MaxExtraPoweredOnVms) || $PoweredOnExtraVMs < $MaxExtraPoweredOnVms)
        {
          $VM->RunRevert();
          $PoweredOnExtraVMs++;
          $RevertingVMs++;
        }
      }
      else
      {
        $VM->RunRevert();
        $RevertingVMs++;
      }
    }
  }
  foreach $VMKey (@{$HostVMs->GetKeys()})
  {
    my $VM = $HostVMs->GetItem($VMKey);
    if (! defined($DirtyVMsBlockingJobs{$VMKey}) &&
        (! defined($MaxRevertingVMs) || $RevertingVMs < $MaxRevertingVMs) &&
        $VM->Status eq 'dirty' && $VM->Type ne "extra" &&
        $VM->Type ne "retired")
    {
      $VM->RunRevert();
      $RevertingVMs++;
    }
  }

  return undef;
}

=pod
=over 12

=item C<Schedule()>

Goes through the WineTestBot hosts and schedules the Job tasks on each of
them using WineTestBot::Jobs::ScheduleOnHost().

=back
=cut

sub Schedule
{
  my $self = shift;

  my $VMs = CreateVMs();
  my %Hosts;
  foreach my $VMKey (@{$VMs->GetKeys()})
  {
    my $VM = $VMs->GetItem($VMKey);
    my $Host = $VM->GetHost();
    $Hosts{$Host}->{$VM->VirtURI} = 1;
  }
  my $ErrMessage;
  foreach my $Host (keys %Hosts)
  {
    my @HostHypervisors = keys %{$Hosts{$Host}};
    my $HostErrMessage = $self->ScheduleOnHost(\@HostHypervisors);
    if (! defined($ErrMessage))
    {
      $ErrMessage = $HostErrMessage;
    }
  }

  return $ErrMessage;
}

=pod
=over 12

=item C<Check()>

Goes through the list of Jobs, and for each of them updates their status by
checking whether they still have running Steps / Tasks, and whether those
have succeeded or failed.

As a side effect this also updates the status of the WineTestBot::Step and
WineTestBot::Task objects.

=back
=cut

sub Check
{
  my $self = shift;

  $self->AddFilter("Status", ["queued", "running"]);
  foreach my $JobKey (@{$self->GetKeys()})
  {
    my $Job = $self->GetItem($JobKey);
    my $Steps = $Job->Steps;
    my $HasQueuedStep = !1;
    my $HasRunningStep = !1;
    my $HasCompletedStep = !1;
    my $HasFailedStep = !1;
    my @SortedSteps = sort { $a->No <=> $b->No } @{$Steps->GetItems()};
    foreach my $Step (@SortedSteps)
    {
      my $Status = $Step->Status;
      if ($Status eq "queued" || $Status eq "running")
      {
        my $Tasks = $Step->Tasks;
        my $HasQueuedTask = !1;
        my $HasRunningTask = !1;
        my $HasCompletedTask = !1;
        my $HasFailedTask = !1;
        foreach my $TaskKey (@{$Tasks->GetKeys()})
        {
          my $Task = $Tasks->GetItem($TaskKey);
          my $Dead = !1;
          if (defined($Task->ChildPid) && ! kill 0 => $Task->ChildPid)
          {
            $Dead = ($! == ESRCH);
          }
          if ($Dead)
          {
            $Task->ChildPid(undef);
            my $Status = $Task->Status;
            if ($Status eq "queued" || $Status eq "running")
            {
              my $OldUMask = umask(002);
              my $TaskDir = "$DataDir/jobs/" . $Job->Id . "/" .  $Step->No . "/" .
                            $Task->No;
              mkdir $TaskDir;
              my $TASKLOG;
              if (open TASKLOG, ">>$TaskDir/log")
              {
                print TASKLOG "Child process died unexpectedly\n";
                close TASKLOG;
              }
              umask($OldUMask);
              LogMsg "Child process for task ", $Job->Id, "/", $Step->No, "/",
                     $Task->No, " died unexpectedly\n";
              $Task->Status("failed");
  
              my $VM = $Task->VM;
              $VM->Status('dirty');
              $VM->Save();
            }
            $Task->Save();
          }
          $Status = $Task->Status;
          if ($HasFailedStep && $Status eq "queued")
          {
            $Status = "skipped";
            $Task->Status("skipped");
          }
          $HasQueuedTask = $HasQueuedTask || $Status eq "queued";
          $HasRunningTask = $HasRunningTask || $Status eq "running";
          $HasCompletedTask = $HasCompletedTask || $Status eq "completed";
          $HasFailedTask = $HasFailedTask || $Status eq "failed";
        }
        if ($HasFailedStep)
        {
          $Step->Status("skipped");
        }
        elsif ($HasRunningTask || ($HasQueuedTask && ($HasCompletedTask ||
                                                      $HasFailedTask)))
        {
          $Step->Status("running");
        }
        elsif ($HasFailedTask)
        {
          $Step->Status("failed");
        }
        elsif ($HasCompletedTask || ! $HasQueuedTask)
        {
          $Step->Status("completed");
        }
        else
        {
          $Step->Status("queued");
        }
        $Step->Save();
      }

      $Status = $Step->Status;
      $HasQueuedStep = $HasQueuedStep || $Status eq "queued";
      $HasRunningStep = $HasRunningStep || $Status eq "running";
      $HasCompletedStep = $HasCompletedStep || $Status eq "completed";
      my $Type = $Step->Type;
      $HasFailedStep = $HasFailedStep ||
                       ($Status eq "failed" &&
                        ($Type eq "build" || $Type eq "reconfig"));
    }

    if ($HasRunningStep || ($HasQueuedStep && ($HasCompletedStep ||
                                               $HasFailedStep)))
    {
      $Job->Status("running");
    }
    elsif ($HasFailedStep)
    {
      if (! defined($Job->Ended))
      {
        $Job->Ended(time);
      }
      $Job->Status("failed");
    }
    elsif ($HasCompletedStep || ! $HasQueuedStep)
    {
      if (! defined($Job->Ended))
      {
        $Job->Ended(time);
      }
      $Job->Status("completed");
    }
    else
    {
      $Job->Status("queued");
    }
    $Job->Save();
  }

  return undef;
}

sub FilterNotArchived
{
  my $self = shift;

  $self->AddFilter("Archived", [!1]);
}

1;
