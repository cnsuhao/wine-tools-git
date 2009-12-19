# Notification of WineTestBot engine
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

WineTestBot::Engine::Notify - Engine notifcation

=cut

package WineTestBot::Engine::Notify;

use Socket;
use WineTestBot::Config;

use vars qw (@ISA @EXPORT @EXPORT_OK $RunningInEngine);

require Exporter;
@ISA = qw(Exporter);
@EXPORT = qw(&PingEngine &JobSubmit &JobStatusChange &TaskComplete
             &VMStatusChange &ExpectWinetestUpdate &FoundWinetestUpdate);
@EXPORT_OK = qw($RunningInEngine);

sub SendCmdReceiveReply
{
  my $Cmd = shift;

  if (defined($RunningInEngine))
  {
    return "1";
  }

  if (! socket(SOCK, PF_UNIX, SOCK_STREAM, 0))
  {
    return "0Unable to create socket: $!";
  }
  if (! connect(SOCK, sockaddr_un("$DataDir/socket/engine")))
  {
    return "0Unable to connect to engine: $!";
  }

  if (! syswrite(SOCK, $Cmd, length($Cmd)))
  {
    return "0Unable to send command to engine: $!";
  }

  my $Reply = "";
  my $Buf;
  while (my $Len = sysread(SOCK, $Buf, 128))
  {
    $Reply .= $Buf;
  }

  close(SOCK);

  return $Reply;
}

sub PingEngine
{
  my $Reply = SendCmdReceiveReply("ping\n");
  return 1 <= length($Reply) && substr($Reply, 0, 1) eq "1";
}

sub JobSubmit
{
  my $JobKey = $_[0];

  my $Reply = SendCmdReceiveReply("jobsubmit $JobKey\n");
  if (length($Reply) < 1)
  {
    return "Unrecognized reply received from engine";
  }
  if (substr($Reply, 0, 1) eq "1")
  {
    return undef;
  }
 
  return substr($Reply, 1);
}

sub JobStatusChange
{
  my ($JobKey, $OldStatus, $NewStatus) = @_;

  my $Reply = SendCmdReceiveReply("jobstatuschange $JobKey $OldStatus $NewStatus\n");
  if (length($Reply) < 1)
  {
    return "Unrecognized reply received from engine";
  }
  if (substr($Reply, 0, 1) eq "1")
  {
    return undef;
  }
 
  return substr($Reply, 1);
}

sub TaskComplete
{
  my ($JobKey, $StepKey, $TaskKey) = @_;

  my $Reply = SendCmdReceiveReply("taskcomplete $JobKey $StepKey $TaskKey\n");
  if (length($Reply) < 1)
  {
    return "Unrecognized reply received from engine";
  }
  if (substr($Reply, 0, 1) eq "1")
  {
    return undef;
  }
 
  return substr($Reply, 1);
}

sub VMStatusChange
{
  my ($VMKey, $OldStatus, $NewStatus) = @_;

  my $Reply = SendCmdReceiveReply("vmstatuschange $VMKey $OldStatus $NewStatus\n");
  if (length($Reply) < 1)
  {
    return "Unrecognized reply received from engine";
  }
  if (substr($Reply, 0, 1) eq "1")
  {
    return undef;
  }
 
  return substr($Reply, 1);
}

sub ExpectWinetestUpdate
{
  my $Reply = SendCmdReceiveReply("expectwinetestupdate\n");
  if (length($Reply) < 1)
  {
    return "Unrecognized reply received from engine";
  }
  if (substr($Reply, 0, 1) eq "1")
  {
    return undef;
  }
 
  return substr($Reply, 1);
}

sub FoundWinetestUpdate
{
  my $Reply = SendCmdReceiveReply("foundwinetestupdate\n");
  if (length($Reply) < 1)
  {
    return "Unrecognized reply received from engine";
  }
  if (substr($Reply, 0, 1) eq "1")
  {
    return undef;
  }
 
  return substr($Reply, 1);
}

1;
