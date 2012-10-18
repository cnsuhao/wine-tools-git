# VM collection and items
#
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

=head1 NAME

WineTestBot::VMs - VM collection

=cut

package WineTestBot::VM::HostConnection;

use VMware::Vix::Simple;
use VMware::Vix::API::Constants;
use WineTestBot::Config;

use vars qw (@ISA @EXPORT_OK);

require Exporter;
@ISA = qw(Exporter);

@EXPORT_OK = qw(new);

sub new
{
  my $class = shift;

  my $self = {};
  $self = bless $self, $class;
  return $self;
}

sub GetHostHandle
{
  my $self = shift;
  my $VixHost = $_[0];

  my $Key = $VixHost || "";
  if (defined($self->{$Key}))
  {
    return (undef, $self->{$Key});
  }

  my ($Err, $HostHandle) = HostConnect(VIX_API_VERSION,
                                       $VixHostType, $VixHost, 0,
                                       $VixHostUsername, $VixHostPassword,
                                       0, VIX_INVALID_HANDLE);
  if ($Err != VIX_OK)
  {
    return (GetErrorText($Err), VIX_INVALID_HANDLE);
  }
  $self->{$Key} = $HostHandle;

  return (undef, $self->{$Key});
}

sub DESTROY
{
  my $self = shift;

  foreach my $HostHandle (values %{$self})
  {
    HostDisconnect($HostHandle);
  }
}

package WineTestBot::VM;

use VMware::Vix::Simple;
use VMware::Vix::API::Constants;

use ObjectModel::BackEnd;
use WineTestBot::Config;
use WineTestBot::Engine::Notify;
use WineTestBot::TestAgent;
use WineTestBot::WineTestBotObjects;
use WineTestBot::Log;

use vars qw (@ISA @EXPORT);

require Exporter;
@ISA = qw(WineTestBot::WineTestBotItem Exporter);

sub _initialize
{
  my $self = shift;
  my $VMs = $_[0];

  $self->{HostConnection} = $VMs->{HostConnection};
  $self->{VMHandle} = VIX_INVALID_HANDLE;
  $self->{LoggedInToGuest} = undef;
  $self->{OldStatus} = undef;
}

sub DESTROY
{
  my $self = shift;

  if ($self->{VMHandle} != VIX_INVALID_HANDLE)
  {
    ReleaseHandle($self->{VMHandle});
    $self->{VMHandle} = VIX_INVALID_HANDLE;
  }
}

sub InitializeNew
{
  my $self = shift;

  $self->Status("Idle");
  $self->IdleSnapshot("winetest_on");

  $self->SUPER::InitializeNew(@_);
}

sub GetVMHandle
{
  my $self = shift;

  if ($self->{VMHandle} != VIX_INVALID_HANDLE)
  {
    return (undef, $self->{VMHandle});
  }

  my $VmxHost = $self->VmxHost;
  my ($ErrMessage, $HostHandle) = $self->{HostConnection}->GetHostHandle($VmxHost);
  if (defined($ErrMessage))
  {
    return ($ErrMessage, VIX_INVALID_HANDLE);
  }

  my $Err = VIX_OK;
  ($Err, $self->{VMHandle}) = VMOpen($HostHandle, $self->VmxFilePath);
  if ($Err != VIX_OK)
  {
    $self->{VMHandle} = VIX_INVALID_HANDLE;
    return (GetErrorText($Err), VIX_INVALID_HANDLE);
  }

  return (undef, $self->{VMHandle});
}

sub CheckError
{
  my $self = shift;
  my $Err = $_[0];

  if ($Err != VIX_OK)
  {
    return GetErrorText($Err);
  }

  return undef;
}

sub LoginInGuest
{
  my $self = shift;
  my $VMHandle = $_[0];
  my $Interactive = $_[1] ? "Y" : "N";

  if (defined($self->{LoggedInToGuest}))
  {
    if ($self->{LoggedInToGuest} eq $Interactive)
    {
      return undef;
    }
    VMLogoutFromGuest($VMHandle);
    delete $self->{LoggedInToGuest};
  }

  my $Try = 0;
  my $Err = -1;
  while ($Err != VIX_OK && $Try < 5)
  {
    $Err = VMLoginInGuest($VMHandle, $VixGuestUsername, $VixGuestPassword,
                          $Interactive eq "Y" ?
                          VIX_LOGIN_IN_GUEST_REQUIRE_INTERACTIVE_ENVIRONMENT :
                          0);
    if ($Err != VIX_OK)
    {
      sleep(15);
    }
    $Try++;
  }
  if ($Err == VIX_OK)
  {
    $self->{LoggedInToGuest} = $Interactive;
  }

  return $self->CheckError($Err);
}

sub UpdateStatus
{
  my $self = shift;
  my $VMHandle = $_[0];

  if ($self->Status eq "offline")
  {
    return undef;
  }

  my ($Err, $PowerState) = GetProperties($VMHandle,
                                         VIX_PROPERTY_VM_POWER_STATE);
  if ($Err != VIX_OK)
  {
    return GetErrorText($Err);
  }
  my $Status;
  if ($PowerState == VIX_POWERSTATE_POWERED_OFF)
  {
    $Status = "dirty";
    $self->Status($Status);
    $self->Save();
  }

  return undef;
}

sub RevertToSnapshot
{
  my $self = shift;
  my $SnapshotName = $_[0];

  my ($ErrMessage, $VMHandle) = $self->GetVMHandle();
  if (defined($ErrMessage))
  {
    return $ErrMessage;
  }

  my ($Err, $SnapshotHandle) = VMGetNamedSnapshot($VMHandle, $SnapshotName);
  if ($Err != VIX_OK)
  {
    return GetErrorText($Err);
  }

  $Err = VMRevertToSnapshot($VMHandle, $SnapshotHandle, VIX_VMPOWEROP_LAUNCH_GUI,
                            VIX_INVALID_HANDLE);
  ReleaseHandle($SnapshotHandle);
  if ($Err != VIX_OK)
  {
    return GetErrorText($Err);
  }

  return $self->UpdateStatus($VMHandle);
}

sub CreateSnapshot
{
  my $self = shift;
  my $SnapshotName = $_[0];

  my ($ErrMessage, $VMHandle) = $self->GetVMHandle();
  if (defined($ErrMessage))
  {
    return $ErrMessage;
  }

  my ($Err, $SnapshotHandle) = VMCreateSnapshot($VMHandle, $SnapshotName, "",
                                                VIX_SNAPSHOT_INCLUDE_MEMORY,
                                                VIX_INVALID_HANDLE);
  if ($Err != VIX_OK)
  {
    ReleaseHandle($SnapshotHandle);
  }
  return $self->CheckError($Err);
}

sub RemoveSnapshot
{
  my $self = shift;
  my $SnapshotName = $_[0];

  my ($ErrMessage, $VMHandle) = $self->GetVMHandle();
  if (defined($ErrMessage))
  {
    return $ErrMessage;
  }

  my ($Err, $SnapshotHandle) = VMGetNamedSnapshot($VMHandle, $SnapshotName);
  if ($Err != VIX_OK)
  {
    return GetErrorText($Err);
  }

  $Err = VMRemoveSnapshot($VMHandle, $SnapshotHandle, 0);
  ReleaseHandle($SnapshotHandle);
  return $self->CheckError($Err);
}

sub PowerOn
{
  my $self = shift;

  my ($ErrMessage, $VMHandle) = $self->GetVMHandle();
  if (defined($ErrMessage))
  {
    return $ErrMessage;
  }

  my $Err = VMPowerOn($VMHandle, VIX_VMPOWEROP_NORMAL, VIX_INVALID_HANDLE);
  if ($Err != VIX_OK)
  {
    return GetErrorText($Err);
  }

  return $self->UpdateStatus($VMHandle);
}

sub PowerOff
{
  my $self = shift;

  my ($ErrMessage, $VMHandle) = $self->GetVMHandle();
  if (defined($ErrMessage))
  {
    return $ErrMessage;
  }

  my $Err = VMPowerOff($VMHandle, VIX_VMPOWEROP_NORMAL);
  if ($Err != VIX_OK && $Err != VIX_E_VM_NOT_RUNNING)
  {
    return GetErrorText($Err);
  }

  return $self->UpdateStatus($VMHandle);
}

sub WaitForToolsInGuest($;$)
{
  my ($self, $Timeout) = @_;

  $Timeout ||= $WaitForToolsInVM;
  LogMsg("Waiting for ", $self->Name, " (up to ${Timeout}s)\n");
  my ($Status, $Err) = TestAgent::GetStatus($self->Hostname, $Timeout);
  # In fact we don't care about the status
  return $Err;
}

sub CopyFileFromHostToGuest($$$)
{
  my ($self, $HostPathName, $GuestPathName) = @_;
  return TestAgent::SendFile($self->Hostname,  $HostPathName, $GuestPathName);
}

sub CopyFileFromGuestToHost($$$)
{
  my ($self, $GuestPathName, $HostPathName) = @_;
  return TestAgent::GetFile($self->Hostname,  $GuestPathName, $HostPathName);
}

sub RunScriptInGuestTimeout($$$)
{
  my ($self, $ScriptText, $Timeout) = @_;
  return TestAgent::RunScript($self->Hostname, $ScriptText, $Timeout);
}

sub CaptureScreenImage
{
  my $self = shift;

  my ($ErrMessage, $VMHandle) = $self->GetVMHandle();
  if (defined($ErrMessage))
  {
    return ($ErrMessage, undef, undef);
  }

  $ErrMessage = $self->LoginInGuest($VMHandle, $self->Interactive);
  if (defined($ErrMessage))
  {
    return ($ErrMessage, undef, undef);
  }

  my ($Err, $ImageSize, $ImageBytes) = VMCaptureScreenImage($VMHandle,
                                                            VIX_CAPTURESCREENFORMAT_PNG,
                                                            VIX_INVALID_HANDLE);
  if ($Err != VIX_OK)
  {
    return (GetErrorText($Err), undef, undef);
  }

  return (undef, $ImageSize, $ImageBytes);
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
  if ($NewStatus ne $CurrentStatus)
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
      VMStatusChange($self->GetKey(), $self->{OldStatus}, $NewStatus);
    }
  }
}

sub RunRevert
{
  my $self = shift;

  $self->Status("reverting");
  $self->Save();

  $self->GetBackEnd()->PrepareForFork();
  my $Pid = fork;
  if (defined($Pid) && ! $Pid)
  {
    $ENV{PATH} = "/usr/bin:/bin";
    delete $ENV{ENV};
    exec("$BinDir/RevertVM.pl", $self->GetKey());
    exit;
  }
  if (! defined($Pid))
  {
    return "Unable to start child process: $!";
  }

  return undef;
}

package WineTestBot::VMs;

use VMware::Vix::Simple;
use VMware::Vix::API::Constants;
use ObjectModel::BasicPropertyDescriptor;
use ObjectModel::EnumPropertyDescriptor;
use ObjectModel::PropertyDescriptor;
use WineTestBot::WineTestBotObjects;

use vars qw (@ISA @EXPORT @PropertyDescriptors);

require Exporter;
@ISA = qw(WineTestBot::WineTestBotCollection Exporter);
@EXPORT = qw(&CreateVMs);

sub _initialize
{
  my $self = shift;

  $self->{HostConnection} = WineTestBot::VM::HostConnection->new();

  $self->SUPER::_initialize(@_);
}

BEGIN
{
  @PropertyDescriptors = (
    CreateBasicPropertyDescriptor("Name", "VM name", 1, 1, "A", 20),
    CreateEnumPropertyDescriptor("Type", "Type of VM", !1, 1, ['extra', 'base', 'build', 'retired']),
    CreateBasicPropertyDescriptor("SortOrder", "Display order", !1, 1, "N", 3),
    CreateEnumPropertyDescriptor("Bits", "32 or 64 bits", !1, 1, ['32', '64']),
    CreateEnumPropertyDescriptor("Status", "Current status", !1, 1, ['dirty', 'reverting', 'sleeping', 'idle', 'running', 'offline']),
    CreateBasicPropertyDescriptor("VmxHost", "Host where VM is located", !1, !1, "A", 64),
    CreateBasicPropertyDescriptor("VmxFilePath", "Path to .vmx file", !1, 1, "A", 64),
    CreateBasicPropertyDescriptor("IdleSnapshot", "Name of idle snapshot", !1, 1, "A", 32),
    CreateBasicPropertyDescriptor("Hostname", "The VM hostname", !1, 1, "A", 64),
    CreateBasicPropertyDescriptor("Interactive", "Needs interactive flag", !1, 1, "B", 1),
    CreateBasicPropertyDescriptor("Description", "Description", !1, !1, "A", 40),
  );
}

sub CreateItem
{
  my $self = shift;

  return WineTestBot::VM->new($self);
}

sub CreateVMs
{
  return WineTestBot::VMs::->new("VMs", "VMs", "VM", \@PropertyDescriptors);
}

sub CountRevertingRunningVMs
{
  my $self = shift;

  my $RevertingVMs = 0;
  my $RunningVMs = 0;

  foreach my $VMKey (@{$self->GetKeys()})
  {
    my $VMStatus = $self->GetItem($VMKey)->Status;

    if ($VMStatus eq "reverting")
    {
      $RevertingVMs++;
    }
    if ($VMStatus eq "running")
    {
      $RunningVMs++;
    }
  }

  return ($RevertingVMs, $RunningVMs);
}

sub CountPoweredOnExtraVMs
{
  my $self = shift;

  my $PowerdOnVMs = 0;
  foreach my $VMKey (@{$self->GetKeys()})
  {
    my $VM = $self->GetItem($VMKey);
    my $VMStatus = $VM->Status;

    if (($VM->Type eq "extra" ||
         $VM->Type eq "retired") &&
        ($VMStatus eq "reverting" ||
         $VMStatus eq "sleeping" ||
         $VMStatus eq "idle" ||
         $VMStatus eq "running"))
    {
      $PowerdOnVMs++;
    }
  }

  return $PowerdOnVMs;
}

sub SortKeysBySortOrder
{
  my $self = shift;
  my $Keys = $_[0];

  my %SortOrder;
  foreach my $Key (@$Keys)
  {
    $SortOrder{$Key} = $self->GetItem($Key)->SortOrder;
  }

  my @SortedKeys = sort { $SortOrder{$a} <=> $SortOrder{$b} } @$Keys;
  return \@SortedKeys;
}

sub FilterHost
{
  my $self = shift;
  my $Host = $_[0];

  $self->AddFilter("VmxHost", $Host);
}

1;
