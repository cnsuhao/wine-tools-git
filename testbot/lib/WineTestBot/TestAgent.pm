# Interface with testagentd to send to and receive files from the VMs and
# to run scripts.
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

package TestAgent;
use strict;

use WineTestBot::Config;
use WineTestBot::Log;

my $DONE_READING = 0;
my $DONE_WRITING = 1;


sub create_ip_socket(@)
{
  my $socket;
  eval { $socket = IO::Socket::IP->new(@_); };
  return $socket;
}

sub create_inet_socket(@)
{
  return IO::Socket::INET->new(@_);
}

my $create_socket = \&create_ip_socket;
eval "use IO::Socket::IP";
if ($@)
{
  use IO::Socket::INET;
  $create_socket = \&create_inet_socket;
}

sub _Connect($;$)
{
  my ($Hostname, $Timeout) = @_;

  $Timeout ||= 10;
  my $Deadline = time() + $Timeout;
  while (1)
  {
    my $ConnectTimeout = $Timeout < 30 ? $Timeout : 30;
    my $socket = &$create_socket(PeerHost => $Hostname, PeerPort => $AgentPort,
                                 Type => SOCK_STREAM, Timeout => $ConnectTimeout);
    return $socket if ($socket);

    $Timeout = $Deadline - time();
    last if ($Timeout <= 0);
    # We ignore the upcoming delay in our timeout calculation

    sleep(1);
    # We will retry just in case this is a temporary network failure
  }
  $@ = "Unable to connect to $Hostname:$AgentPort: $@";
  return undef;
}

sub _ReadStatus($$)
{
  my ($fh, $Timeout) = @_;
  my ($Status, $Err) = ("", undef);
  eval
  {
    local $SIG{ALRM} = sub { die "read status timed out\n" }; # NB: \n required
    alarm($Timeout || 10);
    while ($Status !~ /\n/)
    {
      # Note that the status is the last thing we read from the file descriptor
      # so we don't worry about reading too much
      my $Buffer;
      my $n = sysread($fh, $Buffer, 1024);
      if (!defined $n)
      {
        $Err = $!;
        last;
      }
      last if ($n == 0);
      $Status .= $Buffer;
    }
    alarm(0);
  };
  return (undef, $Err) if ($Err);
  return (undef, $@) if ($@);
  return ($Status, undef);
}

sub GetStatus($;$)
{
  my ($Hostname, $Timeout) = @_;

  my $nc = _Connect($Hostname, $Timeout);
  return (undef, $@) if (!$nc);
  $nc->send("status\n", 0);
  $nc->shutdown($DONE_WRITING);
  my ($Status, $Err) = _ReadStatus($nc, $Timeout);
  close($nc);
  return ($Status, $Err);
}

# This is a workaround for bug #8611 which affects File::Copy::copy(),
# causing the script to die instantly if we cannot write to the destination
# file descriptor.
# http://www.nntp.perl.org/group/perl.perl5.porters/2002/02/msg52726.html
sub _Copy($$)
{
    my ($src, $dst) = @_;

    while (1)
    {
        my $buf;
        my $r = sysread($src, $buf, 4096);
        return 0 if (!defined $r);
        last if ($r == 0);
        my $w = syswrite($dst, $buf, $r);
        return 0 if (!defined $w);
        return 0 if ($w != $r);
    }
    return 1;
}

sub SendFile($$$)
{
  my ($Hostname, $LocalPathName, $ServerPathName) = @_;
  LogMsg "SendFile $LocalPathName -> $Hostname $ServerPathName\n";

  my $fh;
  if (!open($fh, "<", $LocalPathName))
  {
    return "unable to open '$LocalPathName' for reading: $!";
  }

  my $Err;
  my $nc = _Connect($Hostname);
  if ($nc)
  {
    $nc->send("write\n$ServerPathName\n", 0);
    $Err = $! if (!_Copy($fh, $nc));
    $nc->shutdown($DONE_WRITING);

    # Now get the status
    my $Status;
    ($Status, $Err) = _ReadStatus($nc, 10);
    $Err = !$Status ? $! : ($Status =~ /^ok:/ ? undef : $Status);
    close($nc);
  }
  else
  {
    $Err = $@;
  }
  close($fh);
  return $Err;
}

sub GetFile($$$)
{
  my ($Hostname, $ServerPathName, $LocalPathName) = @_;
  LogMsg "GetFile $Hostname $ServerPathName -> $LocalPathName\n";

  my $fh;
  if (!open($fh, ">", $LocalPathName))
  {
    return "unable to open '$LocalPathName' for writing: $!";
  }

  my ($Err, $ServerSize);
  my $nc = _Connect($Hostname);
  if ($nc)
  {
    $nc->send("read\n$ServerPathName\n", 0);
    # The status of the open operation is returned first so it does not
    # get mixed up with the file data. However we must not mix buffered
    # (<> or read()) and unbuffered (File:Copy::copy()) read operations on
    # the socket.
    if (sysread($nc, $Err, 1024) <= 0)
    {
      $Err = $!;
    }
    elsif ($Err =~ s/^ok: size=(-?[0-9]+)\n//)
    {
      $ServerSize = $1;
      if ($Err ne "" and syswrite($fh, $Err, length($Err)) < 0)
      {
        $Err = $!;
      }
      else
      {
        $Err = _Copy($nc, $fh) ? undef : $!;
      }
    }
    close($nc);
  }
  else
  {
    $Err = $@;
  }
  close($fh);
  my $LocalSize = -s $LocalPathName;
  if (!defined $Err and $LocalSize != $ServerSize)
  {
    # Something still went wrong during the transfer. Get the last operation
    # status
    my $StatusErr;
    ($Err, $StatusErr) = GetStatus($Hostname);
    $Err = $StatusErr if (!defined $StatusErr);
  }
  unlink $LocalPathName if ($Err);
  return $Err;
}

sub RunScript($$$)
{
  my ($Hostname, $ScriptText, $Timeout) = @_;
  LogMsg "RunScript $Hostname ", ($Timeout || 0), " [$ScriptText]\n";

  my $Err;
  my $nc = _Connect($Hostname);
  if ($nc)
  {
    $nc->send("runscript\n$ScriptText", 0);
    $nc->shutdown($DONE_WRITING);
    my $Status;
    ($Status, $Err) = _ReadStatus($nc, $Timeout);
    $Err = $Status if (defined $Status and $Status !~ /^ok:/);
    close($nc);
    if (!$Err)
    {
      $nc = _Connect($Hostname);
      if ($nc)
      {
        $nc->send("waitchild\n", 0);
        my $Status;
        ($Status, $Err) = _ReadStatus($nc, $Timeout);
        $nc->shutdown($DONE_WRITING);
        $Err = $Status if (defined $Status and $Status !~ /^ok:/);
        close($nc);
      }
      else
      {
        $Err = $@;
      }
    }
  }
  else
  {
    $Err = $@;
  }
  return $Err;
}

1;
