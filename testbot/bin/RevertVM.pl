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
my $Name0 = $0;
$Name0 =~ s+^.*/++;

use WineTestBot::Config;
use WineTestBot::Log;
use WineTestBot::VMs;

my $Debug;
sub Debug(@)
{
  print STDERR @_ if ($Debug);
}

sub Error(@)
{
  Debug("$Name0:error: ", @_);
  LogMsg @_;
}

sub FatalError($$)
{
  my ($ErrMessage, $VM) = @_;
  Error $ErrMessage;

  # Get the up-to-date VM status and update it if nobody else changed it
  my $VMKey = $VM->GetKey();
  $VM = CreateVMs()->GetItem($VMKey);
  if ($VM->Status eq "reverting" or $VM->Status eq "sleeping")
  {
    $VM->Status("offline");
    $VM->ChildPid(undef);
    $VM->Save();
  }

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

  exit 1;
}

$ENV{PATH} = "/usr/bin:/bin";
delete $ENV{ENV};


# Grab the command line options
my ($Usage, $VMKey);
while (@ARGV)
{
  my $Arg = shift @ARGV;
  if ($Arg eq "--debug")
  {
    $Debug = 1;
  }
  elsif ($Arg =~ /^(?:-\?|-h|--help)$/)
  {
    $Usage = 0;
    last;
  }
  elsif ($Arg =~ /^-/)
  {
    Error "unknown option '$Arg'\n";
    $Usage = 2;
    last;
  }
  elsif (!defined $VMKey)
  {
    $VMKey = $Arg;
  }
  else
  {
    Error "unexpected argument '$Arg'\n";
    $Usage = 2;
    last;
  }
}

# Check parameters
if (!defined $Usage)
{
  if (!defined $VMKey)
  {
    Error "you must specify the VM name\n";
    $Usage = 2;
  }
  elsif ($VMKey =~ /^([a-zA-Z0-9_]+)$/)
  {
    $VMKey = $1;
  }
  else
  {
    Error "'$VMKey' is not a valid VM name\n";
    $Usage = 2;
  }

}
if (defined $Usage)
{
    print "Usage: $Name0 [--debug] [--help] VMName\n";
    exit $Usage;
}

my $VM = CreateVMs()->GetItem($VMKey);
if (!defined $VM)
{
  Error "VM $VMKey does not exist\n";
  exit 1;
}
if (!$Debug and $VM->Status ne "reverting")
{
  FatalError "The VM is not ready to be reverted (" . $VM->Status . ")\n", $VM;
}
my $Start = Time();
LogMsg "Reverting $VMKey to ", $VM->IdleSnapshot, "\n";

# Some QEmu/KVM versions are buggy and cannot revert a running VM
Debug(Elapsed($Start), " Powering off the VM\n");
my $ErrMessage = $VM->PowerOff(1);
if (defined $ErrMessage)
{
  Error "$ErrMessage\n";
  LogMsg "Trying the revert anyway\n";
}

Debug(Elapsed($Start), " Reverting $VMKey to ", $VM->IdleSnapshot, "\n");
$ErrMessage = $VM->RevertToSnapshot($VM->IdleSnapshot);
if (defined($ErrMessage))
{
  FatalError "Could not revert $VMKey to " . $VM->IdleSnapshot . ": $ErrMessage\n",
             $VM;
}

# Get the up-to-date VM status and exit if someone else changed it
$VM = CreateVMs()->GetItem($VMKey);
exit 1 if ($VM->Status ne "reverting");
$VM->Status("sleeping");
(my $ErrProperty, $ErrMessage) = $VM->Save();
if (defined($ErrMessage))
{
  FatalError "Could not change status for VM $VMKey: $ErrMessage\n", $VM;
}

Debug(Elapsed($Start), " Trying the TestAgent connection\n");
LogMsg "Waiting for ", $VM->Name, " (up to ${WaitForToolsInVM}s per attempt)\n";
my $TA = $VM->GetAgent();
$TA->SetConnectTimeout($WaitForToolsInVM);
my $Success = $TA->Ping();
$TA->Disconnect();
if (!$Success)
{
  $ErrMessage = $TA->GetLastError();
  FatalError "Tools in $VMKey not responding: $ErrMessage\n", $VM;
}

if ($SleepAfterRevert != 0)
{
  Debug(Elapsed($Start), " Sleeping\n");
  LogMsg "Letting ", $VM->Name, " settle for ${SleepAfterRevert}s\n";
  sleep($SleepAfterRevert);
}
Debug(Elapsed($Start), " Done\n");

# Get the up-to-date VM status and exit if someone else changed it
$VM = CreateVMs()->GetItem($VMKey);
exit 1 if ($VM->Status ne "sleeping");
$VM->Status("idle");
$VM->ChildPid(undef);
($ErrProperty, $ErrMessage) = $VM->Save();
if (defined($ErrMessage))
{
  FatalError "Could not change status for VM $VMKey: $ErrMessage\n", $VM;
}

LogMsg "Revert of $VMKey completed\n";

exit 0;
