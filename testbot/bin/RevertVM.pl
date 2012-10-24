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

my $Dir;
sub BEGIN
{
  $0 =~ m=^(.*)/[^/]*$=;
  $Dir = $1;
}
use lib "$Dir/../lib";

use WineTestBot::Config;
use WineTestBot::Log;
use WineTestBot::VMs;

sub FatalError
{
  my ($ErrMessage, $VM) = @_;

  my $VMKey = defined($VM) ? $VM->GetKey() : "";

  LogMsg $ErrMessage, "\n";

  if ($VM)
  {
    $VM->Status("offline");
    $VM->Save();
  }

  open (SENDMAIL, "|/usr/sbin/sendmail -oi -t -odq");
  print SENDMAIL <<"EOF";
From: <$RobotEMail> (Marvin)
To: $AdminEMail
Subject: VM $VMKey offline

Reverting $VMKey resulted in error "$ErrMessage". The VM has been put offline.
EOF
  close(SENDMAIL);

  exit 1;
}

$ENV{PATH} = "/usr/bin:/bin";
delete $ENV{ENV};

my ($VMKey) = @ARGV;
if (! $VMKey)
{
  die "Usage: RevertVM.pl VMName";
}

LogMsg "Revert of $VMKey started\n";

my $VMs = CreateVMs();
my $VM = $VMs->GetItem($VMKey);
if (! defined($VM))
{
  FatalError "VM $VMKey doesn't exist";
}

$VM->Status("reverting");
my ($ErrProperty, $ErrMessage) = $VM->Save();
if (defined($ErrMessage))
{
  FatalError "Can't change status for VM $VMKey: $ErrMessage", $VM;
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

foreach my $WaitCount (1..3)
{
  $ErrMessage = $VM->WaitForToolsInGuest();
  if (! defined($ErrMessage))
  {
    last;
  }
}
if (defined($ErrMessage))
{
  LogMsg "$VMKey Error while waiting for tools: $ErrMessage\n";
}

if ($SleepAfterRevert != 0)
{
  sleep($SleepAfterRevert);
}

$VM->Status("idle");
($ErrProperty, $ErrMessage) = $VM->Save();
if (defined($ErrMessage))
{
  FatalError "Can't change status for VM $VMKey: $ErrMessage", $VM;
}

LogMsg "Revert of $VMKey completed\n";

exit;
