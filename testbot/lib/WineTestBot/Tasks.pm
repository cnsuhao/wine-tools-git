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

package WineTestBot::Task;

=head1 NAME

WineTestBot::Task - A task associated with a given WineTestBot::Step object

=head1 DESCRIPTION

A WineTestBot::Step is composed of one or more Tasks, each responsible for
performing that Step in a WineTestBot::VM virtual machine. For instance a Step
responsible for running a given test would have one Task object for each
virtual machine that the test must be performed in.

=cut

use POSIX qw(:errno_h);
use ObjectModel::BackEnd;
use WineTestBot::Config;
use WineTestBot::Jobs;
use WineTestBot::Steps;
use WineTestBot::WineTestBotObjects;
use WineTestBot::Log;

use vars qw(@ISA @EXPORT);

require Exporter;
@ISA = qw(WineTestBot::WineTestBotItem Exporter);

sub InitializeNew
{
  my $self = shift;
  my ($Collection) = @_;

  $self->Status("queued");
  my $Keys = $Collection->GetKeys();
  $self->No(scalar @$Keys + 1);

  $self->SUPER::InitializeNew(@_);
}

=pod
=over 12

=item C<Run()>

Starts a script in the background to execute the specified task. The command is
of the form:

    ${ProjectName}Run${Type}.pl ${JobId} ${StepNo} ${TaskNo}

Where $Type corresponds to the Task's type.

=back
=cut

sub Run
{
  my $self = shift;
  my ($JobId, $StepNo) = @_;

  $self->Status("running");
  $self->Save();

  my $Job = WineTestBot::Jobs::CreateJobs()->GetItem($JobId);
  my $Step = $Job->Steps->GetItem($StepNo);
  my $RunScript;
  if ($Step->Type eq "build")
  {
    $RunScript = "RunBuild.pl";
  }
  elsif ($Step->Type eq "reconfig")
  {
    $RunScript = "RunReconfig.pl";
  }
  else
  {
    $RunScript = "RunTask.pl";
  }
  $Step = undef;
  $Job = undef;

  $self->GetBackEnd()->PrepareForFork();
  my $Pid = fork;
  if (!defined $Pid)
  {
    return "Unable to fork for ${ProjectName}$RunScript: $!";
  }
  elsif (!$Pid)
  {
    # Capture Perl errors in the task's generic error log
    my $TaskDir = "$DataDir/jobs/$JobId/$StepNo/" . $self->No;
    mkdir $TaskDir;
    unlink "$TaskDir/err"; # truncate the log since this is a new run
    if (open(STDERR, ">>", "$TaskDir/err"))
    {
      # Make sure stderr still flushes after each print
      my $tmp=select(STDERR);
      $| = 1;
      select($tmp);
    }
    else
    {
      LogMsg "unable to redirect stderr to '$TaskDir/err': $!\n";
    }
    $ENV{PATH} = "/usr/bin:/bin";
    delete $ENV{ENV};
    exec("$BinDir/${ProjectName}$RunScript", $JobId, $StepNo, $self->No) or
    require WineTestBot::Log;
    WineTestBot::Log::LogMsg("Unable to exec ${ProjectName}$RunScript: $!\n");
    exit(1);
  }

  # Note that if the child process completes quickly (typically due to some
  # error), it may set ChildPid to undef before we get here. So we may end up
  # with non-running tasks for which ChildPid is set. That's ok because
  # ChildPid should be ignored anyway if Status is not 'running'.
  $self->ChildPid($Pid);
  $self->Started(time);
  my ($ErrProperty, $ErrMessage) = $self->Save();

  return $ErrMessage;
}

sub UpdateStatus
{
  my ($self, $Skip) = @_;

  my $Status = $self->Status;

  if (defined $self->ChildPid && !kill(0, $self->ChildPid) && $! == ESRCH)
  {
    $self->ChildPid(undef);
    if ($Status eq "queued" || $Status eq "running")
    {
      my ($JobId, $StepNo, $TaskNo) = @{$self->GetMasterKey()};
      my $OldUMask = umask(002);
      my $TaskDir = "$DataDir/jobs/$JobId/$StepNo/$TaskNo";
      mkdir $TaskDir;
      if (open TASKLOG, ">>$TaskDir/err")
      {
        print TASKLOG "Child process died unexpectedly\n";
        close TASKLOG;
      }
      umask($OldUMask);
      # This probably indicates a bug in the task script.
      # Don't requeue the task to avoid an infinite loop.
      LogMsg "Child process for task $JobId/$StepNo/$TaskNo died unexpectedly\n";
      $self->Status("boterror");
      $Status = "boterror";

      my $VM = $self->VM;
      $VM->Status('dirty');
      $VM->Save();
    }
    $self->Save();
  }
  elsif ($Skip && $Status eq "queued")
  {
    $Status = "skipped";
    $self->Status("skipped");
    $self->Save();
  }
  return $Status;
}


package WineTestBot::Tasks;

=head1 NAME

WineTestBot::Tasks - A collection of WineTestBot::Task objects

=cut

use ObjectModel::BasicPropertyDescriptor;
use ObjectModel::EnumPropertyDescriptor;
use ObjectModel::ItemrefPropertyDescriptor;
use ObjectModel::PropertyDescriptor;
use WineTestBot::VMs;
use WineTestBot::WineTestBotObjects;

use vars qw(@ISA @EXPORT @PropertyDescriptors);

require Exporter;
@ISA = qw(WineTestBot::WineTestBotCollection Exporter);
@EXPORT = qw(&CreateTasks);

BEGIN
{
  @PropertyDescriptors = (
    CreateBasicPropertyDescriptor("No", "Task no",  1,  1, "N", 2),
    CreateEnumPropertyDescriptor("Status", "Status",  !1,  1, ['queued', 'running', 'completed', 'badpatch', 'badbuild', 'boterror', 'canceled', 'skipped']),
    CreateItemrefPropertyDescriptor("VM", "VM", !1,  1, \&CreateVMs, ["VMName"]),
    CreateBasicPropertyDescriptor("Timeout", "Timeout", !1, 1, "N", 4),
    CreateBasicPropertyDescriptor("CmdLineArg", "Command line args", !1, !1, "A", 256),
    # Note: ChildPid is only valid when Status == 'running'.
    CreateBasicPropertyDescriptor("ChildPid", "Child process id", !1, !1, "N", 5),
    CreateBasicPropertyDescriptor("Started", "Execution started", !1, !1, "DT", 19),
    CreateBasicPropertyDescriptor("Ended", "Execution ended", !1, !1, "DT", 19),
    CreateBasicPropertyDescriptor("TestFailures", "Number of test failures", !1, !1, "N", 6),
  );
}

sub CreateItem
{
  my $self = shift;

  return WineTestBot::Task->new($self);
}

sub CreateTasks
{
  my $Step = shift;

  return WineTestBot::Tasks->new("Tasks", "Tasks", "Task",
                                 \@PropertyDescriptors, $Step);
}

1;
