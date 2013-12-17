#!/usr/bin/perl -Tw
#
# Reverts a VM so that it is ready to run jobs. Note that in addition to the
# hypervisor revert operation this implies letting the VM settle down and
# checking that it responds to our commands. If this fails the administrator
# is notified and the VM is marked as offline.
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

sub BEGIN
{
  if ($0 !~ m=^/=)
  {
    # Turn $0 into an absolute path so it can safely be used in @INC
    require Cwd;
    $0 = Cwd::cwd() . "/$0";
  }
  if ($0 =~ m=^(/.*)/[^/]+/[^/]+$=)
  {
    $::RootDir = $1;
    unshift @INC, "$::RootDir/lib";
  }
}

use WineTestBot::Config;
use WineTestBot::Log;
use WineTestBot::VMs;

sub FatalError
{
  my ($ErrMessage, $VM) = @_;

  LogMsg $ErrMessage, "\n";

  if ($VM)
  {
    $VM->Status("offline");
    $VM->ChildPid(undef);
    $VM->Save();

    my $VMKey = $VM->GetKey();
    my $VMSnapshot = $VM->IdleSnapshot;
    open (SENDMAIL, "|/usr/sbin/sendmail -oi -t -odq");
    print SENDMAIL <<"EOF";
From: $RobotEMail
To: $AdminEMail
Subject: VM $VMKey offline

Reverting $VMKey to $VMSnapshot failed:

$ErrMessage

The VM has been put offline.
EOF
    close(SENDMAIL);
  }

  exit 1;
}

$ENV{PATH} = "/usr/bin:/bin";
delete $ENV{ENV};

my ($VMKey) = @ARGV;
if (! $VMKey)
{
  die "Usage: RevertVM.pl VMName";
}

my $VM = CreateVMs()->GetItem($VMKey);
if (! defined($VM))
{
  FatalError "VM $VMKey doesn't exist";
}

LogMsg "Reverting $VMKey to ", $VM->IdleSnapshot, "\n";
$VM->Status("reverting");
my ($ErrProperty, $ErrMessage) = $VM->Save();
if (defined($ErrMessage))
{
  FatalError "Can't change status for VM $VMKey: $ErrMessage", $VM;
}

# Some QEmu/KVM versions are buggy and cannot revert a running VM
$ErrMessage = $VM->PowerOff(1);
if (defined $ErrMessage)
{
  LogMsg "$ErrMessage\n";
  LogMsg "Trying the revert anyway\n";
}

$ErrMessage = $VM->RevertToSnapshot($VM->IdleSnapshot);
if (defined($ErrMessage))
{
  FatalError "Can't revert $VMKey to " . $VM->IdleSnapshot . ": $ErrMessage",
             $VM;
}

$VM->Status("sleeping");
($ErrProperty, $ErrMessage) = $VM->Save();
if (defined($ErrMessage))
{
  FatalError "Can't change status for VM $VMKey: $ErrMessage", $VM;
}

my $Success;
my $TA = $VM->GetAgent();
$TA->SetConnectTimeout($WaitForToolsInVM);
foreach my $WaitCount (1..3)
{
  LogMsg "Waiting for ", $VM->Name, " (up to ${WaitForToolsInVM}s)\n";
  $Success = $TA->Ping();
  last if ($Success);
}
$TA->Disconnect();
if (!$Success)
{
  $ErrMessage = $TA->GetLastError();
  FatalError "Tools in $VMKey not responding: $ErrMessage", $VM;
}

if ($SleepAfterRevert != 0)
{
  LogMsg "Letting ", $VM->Name, " settle for ${SleepAfterRevert}s\n";
  sleep($SleepAfterRevert);
}

$VM->Status("idle");
$VM->ChildPid(undef);
($ErrProperty, $ErrMessage) = $VM->Save();
if (defined($ErrMessage))
{
  FatalError "Can't change status for VM $VMKey: $ErrMessage", $VM;
}

LogMsg "Revert of $VMKey completed\n";

exit;
