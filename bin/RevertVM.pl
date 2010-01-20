#!/usr/bin/perl -Tw

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

  LogMsg "RevertVM: $VMKey $ErrMessage\n";

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

LogMsg "RevertVM: revert of $VMKey started\n";

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
  LogMsg "RevertVM: $VMKey Error while waiting for tools: $ErrMessage\n";
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

LogMsg "RevertVM: revert of $VMKey completed\n";

exit;
