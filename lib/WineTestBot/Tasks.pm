# Individual task of a job collection and items
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

=head1 NAME

WineTestBot::Tasks - Job task collection

=cut

package WineTestBot::Task;

use ObjectModel::BackEnd;
use WineTestBot::Config;
use WineTestBot::Jobs;
use WineTestBot::Steps;
use WineTestBot::WineTestBotObjects;

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

sub Run
{
  my $self = shift;
  my ($JobId, $StepNo) = @_;

  $self->Status("running");
  $self->Save();

  $self->GetBackEnd()->PrepareForFork();
  my $Pid = fork;
  if (defined($Pid) && ! $Pid)
  {
    my $Jobs = WineTestBot::Jobs::CreateJobs();
    my $Job = $Jobs->GetItem($JobId);
    my $Step = $Job->Steps->GetItem($StepNo);
    my $RunScript;
    if ($Step->Type eq "build")
    {
      $RunScript = "$BinDir/${ProjectName}RunBuild.pl";
    }
    elsif ($Step->Type eq "reconfig")
    {
      $RunScript = "$BinDir/${ProjectName}RunReconfig.pl";
    }
    else
    {
      $RunScript = "$BinDir/${ProjectName}RunTask.pl";
    }
    $Step = undef;
    $Job = undef;
    $Jobs = undef;
    $ENV{PATH} = "/usr/bin:/bin";
    delete $ENV{ENV};
    exec($RunScript, $JobId, $StepNo, $self->No);
    exit;
  }
  if (! defined($Pid))
  {
    return "Unable to start child process: $!";
  }

  $self->ChildPid($Pid);
  $self->Started(time);
  my ($ErrProperty, $ErrMessage) = $self->Save();

  return $ErrMessage;
}

package WineTestBot::Tasks;

use ObjectModel::BasicPropertyDescriptor;
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
  $PropertyDescriptors[0] =
    CreateBasicPropertyDescriptor("No", "Task no",  1,  1, "N", 2);
  $PropertyDescriptors[1] =
    CreateBasicPropertyDescriptor("Status", "Status",  !1,  1, "A", 9);
  $PropertyDescriptors[2] =
    CreateItemrefPropertyDescriptor("VM", "VM", !1,  1, \&CreateVMs, ["VMName"]);
  $PropertyDescriptors[3] =
    CreateBasicPropertyDescriptor("Timeout", "Timeout", !1, 1, "N", 4);
  $PropertyDescriptors[4] =
    CreateBasicPropertyDescriptor("CmdLineArg", "Command line args", !1, !1, "A", 256);
  $PropertyDescriptors[5] =
    CreateBasicPropertyDescriptor("ChildPid", "Process id of child process", !1, !1, "N", 5);
  $PropertyDescriptors[6] =
    CreateBasicPropertyDescriptor("Started", "Execution started", !1, !1, "DT", 19);
  $PropertyDescriptors[7] =
    CreateBasicPropertyDescriptor("Ended", "Execution ended", !1, !1, "DT", 19);
  $PropertyDescriptors[8] =
    CreateBasicPropertyDescriptor("TestFailures", "Number of test failures", !1, !1, "N", 5);
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
