# VM collection and items
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

  my $self = {HostHandle => VIX_INVALID_HANDLE };
  $self = bless $self, $class;
  return $self;
}

sub GetHostHandle
{
  my $self = shift;

  if ($self->{HostHandle} != VIX_INVALID_HANDLE)
  {
    return (undef, $self->{HostHandle});
  }

  my $Err = VIX_OK;
  ($Err, $self->{HostHandle}) = HostConnect(VIX_API_VERSION,
                                            $VixHostType, $VixHostName, 0,
                                            $VixHostUsername, $VixHostPassword,
                                            0, VIX_INVALID_HANDLE);
  if ($Err != VIX_OK)
  {
    $self->{HostHandle} = VIX_INVALID_HANDLE;
    return (GetErrorText($Err), VIX_INVALID_HANDLE);
  }

  return (undef, $self->{HostHandle});
}

sub DESTROY
{
  my $self = shift;

  if ($self->{HostHandle} != VIX_INVALID_HANDLE)
  {
    HostDisconnect($self->{HostHandle});
    $self->{HostHandle} = VIX_INVALID_HANDLE;
  }
}

package WineTestBot::VM;

use VMware::Vix::Simple;
use VMware::Vix::API::Constants;
use ObjectModel::Item;
use WineTestBot::Config;
use WineTestBot::Engine::Notify;

use vars qw (@ISA @EXPORT);

require Exporter;
@ISA = qw(ObjectModel::Item Exporter);

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

  my ($ErrMessage, $HostHandle) = $self->{HostConnection}->GetHostHandle();
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

  if (defined($self->{LoggedInToGuest}) &&
      $self->{LoggedInToGuest} eq $Interactive)
  {
    return undef;
  }

  my $Err = VMLoginInGuest($VMHandle, $VixGuestUsername, $VixGuestPassword,
                           $Interactive eq "Y" ?
                           VIX_LOGIN_IN_GUEST_REQUIRE_INTERACTIVE_ENVIRONMENT :
                           0);
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

sub WaitForToolsInGuest
{
  my $self = shift;

  my ($ErrMessage, $VMHandle) = $self->GetVMHandle();
  if (defined($ErrMessage))
  {
    return $ErrMessage;
  }

  my $Err = VMWaitForToolsInGuest($VMHandle, 60);
  return $self->CheckError($Err);
}

sub CopyFileFromHostToGuest
{
  my $self = shift;
  my ($HostPathName, $GuestPathName) = @_;

  my ($ErrMessage, $VMHandle) = $self->GetVMHandle();
  if (defined($ErrMessage))
  {
    return $ErrMessage;
  }

  $ErrMessage = $self->LoginInGuest($VMHandle, !1);
  if (defined($ErrMessage))
  {
    return $ErrMessage;
  }

  my $Err = VMCopyFileFromHostToGuest($VMHandle, $HostPathName, $GuestPathName,
                                      0, VIX_INVALID_HANDLE);
  return $self->CheckError($Err);
}

sub CopyFileFromGuestToHost
{
  my $self = shift;
  my ($GuestPathName, $HostPathName) = @_;

  my ($ErrMessage, $VMHandle) = $self->GetVMHandle();
  if (defined($ErrMessage))
  {
    return $ErrMessage;
  }

  $ErrMessage = $self->LoginInGuest($VMHandle, !1);
  if (defined($ErrMessage))
  {
    return $ErrMessage;
  }

  my $Err = VMCopyFileFromGuestToHost($VMHandle, $GuestPathName, $HostPathName,
                                      0, VIX_INVALID_HANDLE);
  return $self->CheckError($Err);
}

sub RunScriptInGuestTimeout
{
  my $self = shift;
  my ($Interpreter, $ScriptText, $Timeout) = @_;

  my ($ErrMessage, $VMHandle) = $self->GetVMHandle();
  if (defined($ErrMessage))
  {
    return $ErrMessage;
  }

  $ErrMessage = $self->LoginInGuest($VMHandle, $self->Interactive);
  if (defined($ErrMessage))
  {
    return $ErrMessage;
  }

  my $Job = VMware::Vix::API::VM::RunScriptInGuest($VMHandle, $Interpreter,
                                                   $ScriptText, 0,
                                                   VIX_INVALID_HANDLE, undef,
                                                   0);
  my ($Complete, $Err, $Time)  = VMware::Vix::API::Job::WaitTimeout($Job,
                                                                    $Timeout);

  VMware::Vix::API::API::ReleaseHandle($Job);

  if (! $Complete)
  {
    return "Exceeded timeout limit of $Timeout sec";
  }

  return $self->CheckError($Err);
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
use ObjectModel::Collection;
use ObjectModel::PropertyDescriptor;

use vars qw (@ISA @EXPORT @PropertyDescriptors);

require Exporter;
@ISA = qw(ObjectModel::Collection Exporter);
@EXPORT = qw(&CreateVMs);

sub _initialize
{
  my $self = shift;

  $self->{HostConnection} = WineTestBot::VM::HostConnection->new();

  $self->SUPER::_initialize(@_);
}

BEGIN
{
  $PropertyDescriptors[0] =
    CreateBasicPropertyDescriptor("Name", "VM name", 1, 1, "A", 20);
  $PropertyDescriptors[1] =
    CreateBasicPropertyDescriptor("Type", "Type of VM", !1, 1, "A", 5);
  $PropertyDescriptors[2] =
    CreateBasicPropertyDescriptor("SortOrder", "Display order", !1, 1, "N", 3);
  $PropertyDescriptors[3] =
    CreateBasicPropertyDescriptor("Bits", "32 or 64 bits", !1, 1, "N", 2);
  $PropertyDescriptors[4] =
    CreateBasicPropertyDescriptor("Status", "Current status", !1, 1, "A", 9);
  $PropertyDescriptors[5] =
    CreateBasicPropertyDescriptor("VmxFilePath", "Path to .vmx file", !1, 1, "A", 64);
  $PropertyDescriptors[6] =
    CreateBasicPropertyDescriptor("IdleSnapshot", "Name of idle snapshot", !1, 1, "A", 32);
  $PropertyDescriptors[7] =
    CreateBasicPropertyDescriptor("Interactive", "Needs interactive flag", !1, 1, "B", 1);
  $PropertyDescriptors[8] =
    CreateBasicPropertyDescriptor("Description", "Description", !1, !1, "A", 40);
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

1;
