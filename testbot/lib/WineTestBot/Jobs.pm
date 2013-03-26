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

use WineTestBot::Config;
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

=pod
=over 12

=item C<UpdateStatus()>

Updates the status of this job and of its steps and tasks. Part of this means
checking for failed builds and skipping the subsequent tasks, or detecting
dead child processes.

=back
=cut

sub UpdateStatus($)
{
  my $self = shift;

  my $Status = $self->Status;
  return $Status if ($Status ne "queued" && $Status ne "running");

  my (%Has, $Skip);
  my @SortedSteps = sort { $a->No <=> $b->No } @{$self->Steps->GetItems()};
  foreach my $Step (@SortedSteps)
  {
    my $StepStatus = $Step->UpdateStatus($Skip);
    $Has{$StepStatus} = 1;

    my $Type = $Step->Type;
    if ($StepStatus eq "failed" && ($Type eq "build" || $Type eq "reconfig"))
    {
      # The following steps need binaries that this one was supposed to
      # produce. So skip them.
      $Skip = 1;
    }
  }

  # Inherit the steps most significant status.
  # Note that one or more tasks may have been requeued during the cleanup phase
  # of the server startup. So this job may regress from 'running' back to
  # 'queued'. This means all possible step status values must be considered.
  foreach my $StepStatus ("running", "failed", "skipped", "completed", "queued")
  {
    if ($Has{$StepStatus})
    {
      if ($Has{"queued"})
      {
        # Either nothing ran so this job is still / again 'queued', or not
        # everything has been run yet which means it's still 'running'.
        $Status = $StepStatus eq "queued" ? "queued" : "running";
      }
      else
      {
        # If all steps are skipped it's because the user canceled the job. In
        # that case mark the job as 'failed'.
        $Status = $StepStatus eq "skipped" ? "failed" : $StepStatus;
      }
      $self->Status($Status);
      if ($Status ne "running" && $Status ne "queued" && !defined $self->Ended)
      {
        $self->Ended(time);
      }
      $self->Save();
      last;
    }
  }

  return $Status;
}

sub Cancel
{
  my $self = shift;

  my $Steps = $self->Steps;
  $Steps->AddFilter("Status", ["queued", "running"]);
  foreach my $Step (@{$Steps->GetItems()})
  {
    my $Tasks = $Step->Tasks;
    $Tasks->AddFilter("Status", ["queued", "running"]);
    foreach my $Task (@{$Tasks->GetItems()})
    {
      if ($Task->Status eq "queued")
      {
        $Task->Status("skipped");
        $Task->Save();
      }
      elsif (defined $Task->ChildPid)
      {
        # We don't unset ChildPid so Task::UpdateStatus()
        # will add a trace in the log
        kill("TERM", $Task->ChildPid);
      }
    }
  }
  # Let the higher layers handle updating the overall job status

  return undef;
}

sub Restart
{
  my $self = shift;

  if ($self->Status ne "failed" && $self->Status ne "completed")
  {
    return "Only completed/failed jobs can be restarted";
  }

  my $JobDir = "$DataDir/jobs/" . $self->Id;
  my $FirstStep = 1;
  my $Steps = $self->Steps;
  my @SortedSteps = sort { $a->No <=> $b->No } @{$Steps->GetItems()};
  foreach my $Step (@SortedSteps)
  {
    my $Tasks = $Step->Tasks;
    foreach my $Task (@{$Tasks->GetItems()})
    {
      if ($FirstStep)
      {
        # The first step contains the patch or test executable
        # so only delete its task folders
        system("rm", "-rf", "$JobDir/" . $Step->No . "/" . $Task->No);
      }
      $Task->Status("queued");
      $Task->ChildPid(undef);
      $Task->Started(undef);
      $Task->Ended(undef);
      $Task->TestFailures(undef);
    }
    # Subsequent steps only contain files generated by the previous steps
    system("rm", "-rf", "$JobDir/" . $Step->No) if (!$FirstStep);
    $FirstStep = undef;
    $Step->Status("queued");
  }
  $self->Status("queued");
  $self->Save(); # Save it all

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

use ObjectModel::BasicPropertyDescriptor;
use ObjectModel::EnumPropertyDescriptor;
use ObjectModel::DetailrefPropertyDescriptor;
use ObjectModel::ItemrefPropertyDescriptor;
use ObjectModel::PropertyDescriptor;
use WineTestBot::WineTestBotObjects;
use WineTestBot::Branches;
use WineTestBot::Config;
use WineTestBot::Patches;
use WineTestBot::Steps;
use WineTestBot::Users;
use WineTestBot::VMs;

use vars qw(@ISA @EXPORT @PropertyDescriptors);

require Exporter;
@ISA = qw(WineTestBot::WineTestBotCollection Exporter);
@EXPORT = qw(&CreateJobs &ScheduleJobs &CheckJobs);

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
    CreateBasicPropertyDescriptor("Remarks", "Remarks", !1, !1, "A", 128),
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
  return $a->Priority <=> $b->Priority || $a->Id <=> $b->Id;
}

sub CompareTaskStatus
{
  return $b->Status cmp $a->Status || $a->No <=> $b->No;
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
$MaxNonBasePoweredOnVms setting and the last loop in ScheduleOnHost().

=item *

The number of VMs being reverted on the host at a given time must be kept under
$MaxRevertingVMs. This may be set to 1 in case the hypervisor gets confused
when reverting too many VMs at once.

=item *

No Task is started while there are VMs that are being reverted. This is so that
the tests are not disrupted by the disk or CPU activity caused by reverting a
VM.

=cut

=back
=cut

sub ScheduleOnHost($$)
{
  my ($SortedJobs, $Hypervisors) = @_;

  my $HostVMs = CreateVMs();
  $HostVMs->FilterHypervisor($Hypervisors);
  my ($RevertingVMs, $RunningVMs) = $HostVMs->CountRevertingRunningVMs();
  my $PoweredOnNonBaseVMs = $HostVMs->CountPoweredOnNonBaseVMs();
  my %DirtyVMsBlockingJobs;

  my $DirtyIndex = 0;
  foreach my $Job (@$SortedJobs)
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
        my $VM = $Task->VM;
        my $VMKey = $VM->GetKey();
        if ($Task->Status eq "queued" && $HostVMs->ItemExists($VMKey))
        {
          if ($VM->Status eq "idle" &&
              $RunningVMs < $MaxRunningVMs &&
              $RevertingVMs == 0)
          {
            $VM->Status("running");
            my ($ErrProperty, $ErrMessage) = $VM->Save();
            if (defined($ErrMessage))
            {
              return $ErrMessage;
            }
            $ErrMessage = $Task->Run($Job->Id, $Step->No);
            if (defined($ErrMessage))
            {
              return $ErrMessage;
            }
            $Job->UpdateStatus();
            $RunningVMs++;
          }
          elsif ($VM->Status eq "dirty")
          {
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
    # We don't revert VMs while jobs are running so we're done
    return undef;
  }

  # Sort the VMs by decreasing order of priority of the jobs they block
  my @DirtyVMsByIndex = sort { $DirtyVMsBlockingJobs{$a} <=> $DirtyVMsBlockingJobs{$b} } keys %DirtyVMsBlockingJobs;
  my $VMKey;
  foreach $VMKey (@DirtyVMsByIndex)
  {
    last if ($RevertingVMs >= $MaxRevertingVMs);

    my $VM = $HostVMs->GetItem($VMKey);
    if ($VM->Role ne "base")
    {
      if ($PoweredOnNonBaseVMs < $MaxNonBasePoweredOnVms)
      {
        $VM->RunRevert();
        $PoweredOnNonBaseVMs++;
        $RevertingVMs++;
      }
    }
    else
    {
      $VM->RunRevert();
      $RevertingVMs++;
    }
  }

  # Again for the VMs that don't block any job
  foreach $VMKey (@{$HostVMs->GetKeys()})
  {
    my $VM = $HostVMs->GetItem($VMKey);
    if (! defined($DirtyVMsBlockingJobs{$VMKey}) &&
        $RevertingVMs < $MaxRevertingVMs &&
        $VM->Status eq 'dirty' && $VM->Role eq "base")
    {
      $VM->RunRevert();
      $RevertingVMs++;
    }
  }

  return undef;
}

=pod
=over 12

=item C<ScheduleJobs()>

Goes through the WineTestBot hosts and schedules the Job tasks on each of
them using WineTestBot::Jobs::ScheduleOnHost().

=back
=cut

sub ScheduleJobs()
{
  my $Jobs = CreateJobs();
  $Jobs->AddFilter("Status", ["queued", "running"]);
  my @SortedJobs = sort CompareJobPriority @{$Jobs->GetItems()};
  # Note that even if there are no jobs to schedule
  # we should check if there are VMs to revert

  my %Hosts;
  my $VMs = CreateVMs();
  $VMs->FilterEnabledRole();
  $VMs->FilterEnabledStatus();
  foreach my $VM (@{$VMs->GetItems()})
  {
    my $Host = $VM->GetHost();
    $Hosts{$Host}->{$VM->VirtURI} = 1;
  }

  my @ErrMessages;
  foreach my $Host (keys %Hosts)
  {
    my @HostHypervisors = keys %{$Hosts{$Host}};
    my $HostErrMessage = ScheduleOnHost(\@SortedJobs, \@HostHypervisors);
    push @ErrMessages, $HostErrMessage if (defined $HostErrMessage);
  }
  return @ErrMessages ? join("\n", @ErrMessages) : undef;
}

=pod
=over 12

=item C<CheckJobs()>

Goes through the list of Jobs and updates their status. As a side-effect this
detects failed builds, dead child processes, etc.

=back
=cut

sub CheckJobs()
{
  my $Jobs = CreateJobs();
  $Jobs->AddFilter("Status", ["queued", "running"]);
  map { $_->UpdateStatus(); } @{$Jobs->GetItems()};

  return undef;
}

sub FilterNotArchived
{
  my $self = shift;

  $self->AddFilter("Archived", [!1]);
}

1;
