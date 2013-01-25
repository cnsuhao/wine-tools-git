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

use vars qw (@ISA @EXPORT_OK $SENDFILE_EXE $RUN_DNT);

require Exporter;
@ISA = qw(Exporter);
@EXPORT_OK = qw(new);

my $BLOCK_SIZE = 4096;

my $RPC_PING = 0;
my $RPC_GETFILE = 1;
my $RPC_SENDFILE = 2;
my $RPC_RUN = 3;
my $RPC_WAIT = 4;
my $RPC_RM = 5;

my %RpcNames=(
    $RPC_PING => 'ping',
    $RPC_GETFILE => 'getfile',
    $RPC_SENDFILE => 'sendfile',
    $RPC_RUN => 'run',
    $RPC_WAIT => 'wait',
    $RPC_RM => 'rm',
);

my $Debug = 0;
sub debug(@)
{
    print STDERR @_ if ($Debug);
}

sub new($$$;$)
{
  my ($class, $Hostname, $Port, $Tunnel) = @_;

  my $self = {
    agenthost  => $Hostname,
    host       => $Hostname,
    agentport  => $Port,
    port       => $Port,
    connection => "$Hostname:$Port",
    ctimeout   => 30,
    timeout    => 0,
    fd         => undef,
    deadline   => undef,
    err        => undef};
  if ($Tunnel)
  {
    $self->{host} = $Tunnel->{sshhost} || $Hostname;
    $self->{port} = $Tunnel->{sshport} || 22;
    $self->{connection} = "$self->{host}:$self->{port}:$self->{connection}";
    $self->{tunnel} = $Tunnel;
  }

  $self = bless $self, $class;
  return $self;
}

sub Disconnect($)
{
  my ($self) = @_;

  if ($self->{ssh})
  {
    # This may close the SSH channel ($self->{fd}) as a side-effect,
    # which will avoid undue delays.
    $self->{ssh}->disconnect();
    $self->{ssh} = undef;
  }
  if ($self->{sshfd})
  {
    close($self->{sshfd});
    $self->{sshfd} = undef;
  }
  if ($self->{fd})
  {
      close($self->{fd});
      $self->{fd} = undef;
  }
  $self->{agentversion} = undef;
}

sub SetConnectTimeout($$)
{
  my ($self, $Timeout) = @_;
  my $OldTimeout = $self->{ctimeout};
  $self->{ctimeout} = $Timeout;
  return $OldTimeout;
}

sub SetTimeout($$)
{
  my ($self, $Timeout) = @_;
  my $OldTimeout = $self->{timeout};
  $self->{timeout} = $Timeout;
  return $OldTimeout;
}

sub _SetAlarm($)
{
  my ($self) = @_;
  if ($self->{deadline})
  {
    my $Timeout = $self->{deadline} - time();
    die "timeout" if ($Timeout <= 0);
    alarm($Timeout);
  }
}


#
# Error handling
#

my $ERROR = 0;
my $FATAL = 1;

sub _SetError($$$)
{
  my ($self, $Level, $Msg) = @_;

  # Only overwrite non-fatal errors
  if ($self->{fd})
  {
    # Cleanup errors coming from the server
    $self->{err} = $Msg;

    # And disconnect on fatal errors since the connection is unusable anyway
    $self->Disconnect() if ($Level == $FATAL);
  }
  elsif (!$self->{err})
  {
    # We did not even manage to connect but record the error anyway
    $self->{err} = $Msg;
  }
  debug($RpcNames{$self->{rpcid}} || $self->{rpcid}, ": $self->{err}\n");
}

sub GetLastError($)
{
  my ($self) = @_;
  return $self->{err};
}


#
# Low-level functions to receive raw data
#

sub _RecvRawData($$)
{
  my ($self, $Size) = @_;
  return undef if (!defined $self->{fd});

  my $Result;
  eval
  {
    local $SIG{ALRM} = sub { die "timeout" };
    $self->_SetAlarm();

    my $Data = "";
    while ($Size)
    {
      my $Buffer;
      my $r = $self->{fd}->read($Buffer, $Size);
      if (!defined $r)
      {
        alarm(0);
        $self->_SetError($FATAL, "network read error: $!");
        return;
      }
      if ($r == 0)
      {
        alarm(0);
        $self->_SetError($FATAL, "got a premature network EOF");
        return;
      }
      $Data .= $Buffer;
      $Size -= $r;
    }
    alarm(0);
    $Result = $Data;
  };
  if ($@)
  {
    $@ = "network read timed out" if ($@ =~ /^timeout /);
    $self->_SetError($FATAL, $@);
  }
  return $Result;
}

sub _SkipRawData($$)
{
  my ($self, $Size) = @_;
  return undef if (!defined $self->{fd});

  my $Success;
  eval
  {
    local $SIG{ALRM} = sub { die "timeout" };
    $self->_SetAlarm();

    while ($Size)
    {
      my $Buffer;
      my $s = $Size < $BLOCK_SIZE ? $Size : $BLOCK_SIZE;
      my $n = $self->{fd}->read($Buffer, $s);
      if (!defined $n)
      {
        alarm(0);
        $self->_SetError($FATAL, "network skip failed: $!");
        return;
      }
      if ($n == 0)
      {
        alarm(0);
        $self->_SetError($FATAL, "got a premature network EOF");
        return;
      }
      $Size -= $n;
    }
    alarm(0);
    $Success = 1;
  };
  if ($@)
  {
    $@ = "network skip timed out" if ($@ =~ /^timeout /);
    $self->_SetError($FATAL, $@);
  }
  return $Success;
}

sub _RecvRawUInt32($)
{
  my ($self) = @_;

  my $Data = $self->_RecvRawData(4);
  return undef if (!defined $Data);
  return unpack('N', $Data);
}

sub _RecvRawUInt64($)
{
  my ($self) = @_;

  my $Data = $self->_RecvRawData(8);
  return undef if (!defined $Data);
  my ($High, $Low) = unpack('NN', $Data);
  return $High << 32 | $Low;
}


#
# Low-level functions to result lists
#

sub _RecvEntryHeader($)
{
  my ($self) = @_;

  my $Data = $self->_RecvRawData(9);
  return (undef, undef) if (!defined $Data);
  my ($Type, $High, $Low) = unpack('cNN', $Data);
  $Type = chr($Type);
  return ($Type, $High << 32 | $Low);
}

sub _ExpectEntryHeader($$$)
{
  my ($self, $Type, $Size) = @_;

  my ($HType, $HSize) = $self->_RecvEntryHeader();
  return undef if (!defined $HType);
  if ($HType ne $Type)
  {
    $self->_SetError($ERROR, "Expected a $Type entry but got $HType instead");
  }
  elsif (defined $Size and $HSize != $Size)
  {
    $self->_SetError($ERROR, "Expected an entry of size $Size but got $HSize instead");
  }
  else
  {
    return $HSize;
  }
  if ($HType eq 'e')
  {
    # The expected data was replaced with an error message
    my $Message = $self->_RecvRawData($HSize);
    return undef if (!defined $Message);
    $self->_SetError($ERROR, $Message);
  }
  else
  {
    $self->_SkipRawData($HSize);
  }
  return undef;
}

sub _ExpectEntry($$$)
{
  my ($self, $Type, $Size) = @_;

  $Size = $self->_ExpectEntryHeader($Type, $Size);
  return undef if (!defined $Size);
  return $self->_RecvRawData($Size);
}

sub _RecvUInt32($)
{
  my ($self) = @_;

  return undef if (!defined $self->_ExpectEntryHeader('I', 4));
  my $Value = $self->_RecvRawUInt32();
  debug("  RecvUInt32() -> $Value\n") if (defined $Value);
  return $Value;
}

sub _RecvUInt64($)
{
  my ($self) = @_;

  return undef if (!defined $self->_ExpectEntryHeader('Q', 8));
  my $Value = $self->_RecvRawUInt64();
  debug("  RecvUInt64() -> $Value\n") if (defined $Value);
  return $Value;
}

sub _RecvString($;$)
{
  my ($self, $EType) = @_;

  my $Str = $self->_ExpectEntry($EType || 's');
  if (defined $Str)
  {
    # Remove the trailing '\0'
    chop $Str;
    debug("  RecvString() -> '$Str'\n");
  }
  return $Str;
}

sub _RecvFile($$$)
{
  my ($self, $Dst, $Filename) = @_;
  return undef if (!defined $self->{fd});
  debug("  RecvFile($Filename)\n");

  my $Size = $self->_RecvEntryHeader('d');
  return undef if (!defined $Size);

  my $Success;
  eval
  {
    local $SIG{ALRM} = sub { die "timeout" };
    $self->_SetAlarm();

    while ($Size)
    {
      my $Buffer;
      my $s = $Size < $BLOCK_SIZE ? $Size : $BLOCK_SIZE;
      my $r = $self->{fd}->read($Buffer, $s);
      if (!defined $r)
      {
        alarm(0);
        $self->_SetError($FATAL, "got a network error while receiving '$Filename': $!");
        return;
      }
      if ($r == 0)
      {
        alarm(0);
        $self->_SetError($FATAL, "got a premature EOF while receiving '$Filename'");
        return;
      }
      $Size -= $r;
      my $w = syswrite($Dst, $Buffer, $r, 0);
      if (!defined $w or $w != $r)
      {
        alarm(0);
        $self->_SetError($ERROR, "an error occurred while writing to '$Filename': $!");
        $self->_SkipRawData($Size);
        return;
      }
    }
    alarm(0);
    $Success = 1;
  };
  if ($@)
  {
    $@ = "timed out while receiving '$Filename'" if ($@ =~ /^timeout /);
    $self->_SetError($FATAL, $@);
  }
  return $Success;
}

sub _SkipEntries($$)
{
  my ($self, $Count) = @_;
  debug("  SkipEntries($Count)\n");

  while ($Count)
  {
    my ($Type, $Size) = $self->_RecvEntryHeader();
    return undef if (!defined $Type);
    if ($Type eq 'e')
    {
      # The expected data was replaced with an error message
      my $Message = $self->_RecvRawData($Size);
      return undef if (!defined $Message);
      $self->_SetError($ERROR, $Message);
    }
    elsif (!$self->_SkipRawData($Size))
    {
      return undef;
    }
    $Count--;
  }
  return 1;
}

sub _RecvListSize($)
{
  my ($self) = @_;

  my $Value = $self->_RecvRawUInt32();
  debug("  RecvListSize() -> $Value\n") if (defined $Value);
  return $Value;
}

sub _RecvList($$)
{
  my ($self, $ETypes) = @_;

  debug("  RecvList($ETypes)\n");
  my $HCount = $self->_RecvListSize();
  return undef if (!defined $HCount);

  my $Count = length($ETypes);
  if ($HCount != $Count)
  {
    $self->_SetError($ERROR, "Expected $Count results but got $HCount instead");
    $self->_SkipEntries($HCount);
    return undef;
  }

  my @List;
  foreach my $EType (split //, $ETypes)
  {
    # '.' is a placeholder for data handled by the caller so let it handle
    # the rest
    last if ($EType eq '.');

    my $Data;
    if ($EType eq 'I')
    {
      $Data = $self->_RecvUInt32();
      $Count--;
    }
    elsif ($EType eq 'Q')
    {
      $Data = $self->_RecvUInt64();
      $Count--;
    }
    elsif ($EType eq 's')
    {
      $Data = $self->_RecvString();
      $Count--;
    }
    else
    {
      $self->_SetError($ERROR, "_RecvList() cannot receive a result of type $EType");
    }
    if (!defined $Data)
    {
      $self->_SkipEntries($Count);
      return undef;
    }
    push @List, $Data;
  }
  return 1 if (!@List);
  return $List[0] if (@List == 1);
  return @List;
}

sub _RecvErrorList($)
{
  my ($self) = @_;

  my $Count = $self->_RecvListSize();
  return $self->GetLastError() if (!defined $Count);
  return undef if (!$Count);

  my $Errors = [];
  while ($Count--)
  {
    my ($Type, $Size) = $self->_RecvEntryHeader();
    if ($Type eq 'u')
    {
      debug("  RecvUndef()\n");
      push @$Errors, undef;
    }
    elsif ($Type eq 's')
    {
      my $Status = $self->_RecvRawData($Size);
      return $self->GetLastError() if (!defined $Status);
      debug("  RecvStatus() -> '$Status'\n");
      push @$Errors, $Status;
    }
    elsif ($Type eq 'e')
    {
      # The expected data was replaced with an error message
      my $Message = $self->_RecvRawData($Size);
      if (defined $Message)
      {
        debug("  RecvError() -> '$Message'\n");
        $self->_SetError($ERROR, $Message);
      }
      $self->_SkipEntries($Count);
      return $self->GetLastError();
    }
    else
    {
      $self->_SetError($ERROR, "Expected an s, u or e entry but got $Type instead");
      $self->_SkipRawData($Size);
      $self->_SkipEntries($Count);
      return $self->GetLastError();
    }
  }
  return $Errors;
}


#
# Low-level functions to send raw data
#

sub _Write($$)
{
  my ($self, $Data) = @_;
  return undef if (!defined $self->{fd});

  my $Size = length($Data);
  my $Sent = 0;
  while ($Size)
  {
    my $w = syswrite($self->{fd}, $Data, $Size, $Sent);
    if (!defined $w)
    {
      $self->_SetError($FATAL, "network write error: $!");
      return undef;
    }
    if ($w == 0)
    {
      $self->_SetError($FATAL, "unable to send more data");
      return $Sent;
    }
    $Sent += $w;
    $Size -= $w;
  }
  return $Sent;
}

sub _SendRawData($$)
{
  my ($self, $Data) = @_;
  return undef if (!defined $self->{fd});

  my $Success;
  eval
  {
    local $SIG{ALRM} = sub { die "timeout" };
    $self->_SetAlarm();
    $self->_Write($Data);
    alarm(0);

    # _Write() errors are fatal and break the connection
    $Success = 1 if (defined $self->{fd});
  };
  if ($@)
  {
    $@ = "network write timed out" if ($@ =~ /^timeout /);
    $self->_SetError($FATAL, $@);
  }
  return $Success;
}

sub _SendRawUInt32($$)
{
  my ($self, $Value) = @_;

  return $self->_SendRawData(pack('N', $Value));
}

sub _SendRawUInt64($$)
{
  my ($self, $Value) = @_;

  my ($High, $Low) = ($Value >> 32, $Value & 0xffffffff);
  return $self->_SendRawData(pack('NN', $High, $Low));
}


#
# Functions to send parameter lists
#

sub _SendListSize($$)
{
  my ($self, $Size) = @_;

  debug("  SendListSize($Size)\n");
  return $self->_SendRawUInt32($Size);
}

sub _SendEntryHeader($$$)
{
  my ($self, $Type, $Size) = @_;

  my ($High, $Low) = ($Size >> 32, $Size & 0xffffffff);
  return $self->_SendRawData(pack('cNN', ord($Type), $High, $Low));
}

sub _SendUInt32($$)
{
  my ($self, $Value) = @_;

  debug("  SendUInt32($Value)\n");
  return $self->_SendEntryHeader('I', 4) &&
         $self->_SendRawUInt32($Value);
}

sub _SendUInt64($$)
{
  my ($self, $Value) = @_;

  debug("  SendUInt64($Value)\n");
  return $self->_SendEntryHeader('Q', 8) &&
         $self->_SendRawUInt64($Value);
}

sub _SendString($$;$)
{
  my ($self, $Str, $Type) = @_;

  debug("  SendString('$Str')\n");
  $Str .= "\0";
  return $self->_SendEntryHeader($Type || 's', length($Str)) &&
         $self->_SendRawData($Str);
}

sub _SendFile($$$)
{
  my ($self, $Src, $Filename) = @_;
  return undef if (!defined $self->{fd});
  debug("  SendFile($Filename)\n");

  my $Success;
  eval
  {
    local $SIG{ALRM} = sub { die "timeout" };
    $self->_SetAlarm();

    my $Size = -s $Filename;
    return if (!$self->_SendEntryHeader('d', $Size));
    while ($Size)
    {
      my $Buffer;
      my $s = $Size < $BLOCK_SIZE ? $Size : $BLOCK_SIZE;
      my $r = sysread($Src, $Buffer, $s);
      if (!defined $r)
      {
        alarm(0);
        $self->_SetError($FATAL, "an error occurred while reading from '$Filename': $!");
        return;
      }
      if ($r == 0)
      {
        alarm(0);
        $self->_SetError($FATAL, "got a premature EOF while reading from '$Filename'");
        return;
      }
      $Size -= $r;
      my $w = $self->_Write($Buffer);
      if (!defined $w or $w != $r)
      {
        alarm(0);
        $self->_SetError($FATAL, "got a network error while sending '$Filename': $!");
        return;
      }
    }
    alarm(0);
    $Success = 1;
  };
  if ($@)
  {
    $@ = "timed out while sending '$Filename'" if ($@ =~ /^timeout /);
    $self->_SetError($FATAL, $@);
  }
  return $Success;
}


#
# Connection management functions
#

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

sub _ssherror($)
{
  my ($self) = @_;
  my @List = $self->{ssh}->error();
  return $List[2];
}

sub _Connect($)
{
  my ($self) = @_;

  my $Err;
  eval
  {
    local $SIG{ALRM} = sub { die "timeout" };
    $self->{deadline} = $self->{ctimeout} ? time() + $self->{ctimeout} : undef;
    $self->_SetAlarm();

    while (1)
    {
      $self->{fd} = &$create_socket(PeerHost => $self->{host},
                                    PeerPort => $self->{port},
                                    Type => SOCK_STREAM);
      last if ($self->{fd});
      $Err = $!;
      # Ideally we should probably not retry on errors that are likely
      # permanent, like a hostname that does not resolve. Instead we just
      # rate-limit our connection attempts.
      sleep(1);
    }
    alarm(0);
  };
  if (!$self->{fd})
  {
    $Err ||= $@;
    $Err = "connection timed out" if ($Err =~ /^timeout /);
    $self->_SetError($FATAL, "Unable to connect to $self->{connection}: $Err");
    return undef;
  }

  if ($self->{tunnel})
  {
    # We are in fact connected to the SSH server.
    # Now forward that connection to the TestAgent server.
    $self->{sshfd} = $self->{fd};
    $self->{fd} = undef;

    require Net::SSH2;
    $self->{ssh} = Net::SSH2->new();
    $self->{ssh}->debug(1) if ($Debug > 1);
    if (!$self->{ssh}->connect($self->{sshfd}))
    {
      $self->_SetError($FATAL, "Unable to connect to the SSH server: " . $self->_ssherror());
      return undef;
    }

    # Authenticate ourselves
    my $Tunnel = $self->{tunnel};
    my %AuthOptions=(username => $Tunnel->{username} || $ENV{USER});
    foreach my $Key ("username", "password", "publickey", "privatekey",
                     "hostname", "local_username")
    {
      $AuthOptions{$Key} = $Tunnel->{$Key} if (defined $Tunnel->{$Key});
    }
    # Old versions of Net::SSH2 won't automatically find DSA keys, and new ones
    # still won't automatically find RSA ones.
    if (defined $ENV{HOME} and !exists $AuthOptions{"privatekey"} and
        !exists $AuthOptions{"publickey"})
    {
      foreach my $key ("id_dsa", "id_rsa")
      {
        if (-f "$ENV{HOME}/.ssh/$key" and -f "$ENV{HOME}/.ssh/$key.pub")
        {
          $AuthOptions{"privatekey"} = "$ENV{HOME}/.ssh/$key";
          $AuthOptions{"publickey"} = "$ENV{HOME}/.ssh/$key.pub";
          last;
        }
      }
    }
    # Interactive authentication makes no sense with automatic reconnects
    $AuthOptions{interact} = 0;
    if (!$self->{ssh}->auth(%AuthOptions))
    {
      # auth() returns no error of any sort :-(
      $self->_SetError($FATAL, "Unable to authenticate to the SSH server");
      return undef;
    }

    $self->{fd} = $self->{ssh}->channel();
    if (!$self->{fd})
    {
      $self->_SetError($FATAL, "Unable to create the SSH channel: " . $self->_ssherror());
      return undef;
    }

    # Check that the agent hostname and port won't mess with quoting.
    if ($self->{agenthost} !~ /^[-a-zA-Z0-9.]*$/ or
        $self->{agentport} !~ /^[a-zA-Z0-9]*$/)
    {
      $self->_SetError($FATAL, "The agent hostname or port is invalid");
      return undef;
    }

    # Use netcat to forward the connection from the SSH server to the TestAgent
    # server. Note that we won't know about netcat errors at this point.
    if (!$self->{fd}->exec("nc '$self->{agenthost}' '$self->{agentport}'"))
    {
      $self->_SetError($FATAL, "Unable to start netcat: " . $self->_ssherror());
      return undef;
    }
  }

  # Get the protocol version supported by the server.
  # This also lets us verify that the connection really works.
  $self->{agentversion} = $self->_RecvString();
  if (!defined $self->{agentversion})
  {
    # We have already been disconnected at this point
    $self->{err} = "Unable to get the protocol version spoken by the server: $self->{err}";
    return undef;
  }

  return 1;
}

sub _StartRPC($$)
{
  my ($self, $RpcId) = @_;

  # Set up the new RPC
  $self->{rpcid} = $RpcId;
  $self->{err} = undef;

  # First assume all is well and that we already have a working connection
  $self->{deadline} = $self->{timeout} ? time() + $self->{timeout} : undef;
  if (!$self->_SendRawUInt32($RpcId))
  {
    # No dice, clean up whatever was left of the old connection
    $self->Disconnect();

    # And reconnect
    return undef if (!$self->_Connect());
    debug("Using protocol '$self->{agentversion}'\n");

    # Reconnecting reset the operation deadline
    $self->{deadline} = $self->{timeout} ? time() + $self->{timeout} : undef;
    return $self->_SendRawUInt32($RpcId);
  }
  return 1;
}


#
# Implement the high-level RPCs
#

sub Ping($)
{
  my ($self) = @_;

  # Send the RPC and get the reply
  return $self->_StartRPC($RPC_PING) &&
         $self->_SendListSize(0) &&
         $self->_RecvList('');
}

sub GetVersion($)
{
  my ($self) = @_;

  if (!$self->{agentversion})
  {
    # Force a connection
    $self->Ping();
  }
  # And return the version we got.
  # If the connection failed it will be undef as expected.
  return $self->{agentversion};
}

$SENDFILE_EXE = 1;

sub _SendStringOrFile($$$$$$)
{
  my ($self, $Data, $fh, $LocalPathName, $ServerPathName, $Flags) = @_;

  # Send the RPC and get the reply
  return $self->_StartRPC($RPC_SENDFILE) &&
         $self->_SendListSize(3) &&
         $self->_SendString($ServerPathName) &&
         $self->_SendUInt32($Flags || 0) &&
         ($fh ? $self->_SendFile($fh, $LocalPathName) :
                $self->_SendString($Data, 'd')) &&
         $self->_RecvList('');
}

sub SendFile($$$;$)
{
  my ($self, $LocalPathName, $ServerPathName, $Flags) = @_;
  debug("SendFile $LocalPathName -> $self->{agenthost} $ServerPathName\n");

  if (open(my $fh, "<", $LocalPathName))
  {
    my $Success = $self->_SendStringOrFile(undef, $fh, $LocalPathName,
                                           $ServerPathName, $Flags);
    close($fh);
    return $Success;
  }
  $self->_SetError($ERROR, "Unable to open '$LocalPathName' for reading: $!");
  return undef;
}

sub SendFileFromString($$$;$)
{
  my ($self, $Data, $ServerPathName, $Flags) = @_;
  debug("SendFile String -> $self->{agenthost} $ServerPathName\n");
  return $self->_SendStringOrFile($Data, undef, undef, $ServerPathName, $Flags);
}

sub _GetFileOrString($$$)
{
  my ($self, $ServerPathName, $LocalPathName, $fh) = @_;

  # Send the RPC and get the reply
  my $Success = $self->_StartRPC($RPC_GETFILE) &&
                $self->_SendListSize(1) &&
                $self->_SendString($ServerPathName) &&
                $self->_RecvList('.');
  return undef if (!$Success);
  return $self->_RecvFile($fh, $LocalPathName) if ($fh);
  return $self->_RecvString('d');
}

sub GetFile($$$)
{
  my ($self, $ServerPathName, $LocalPathName) = @_;
  debug("GetFile $self->{agenthost} $ServerPathName -> $LocalPathName\n");

  if (open(my $fh, ">", $LocalPathName))
  {
    my $Success = $self->_GetFileOrString($ServerPathName, $LocalPathName, $fh);
    close($fh);
    return $Success;
  }
  $self->_SetError($ERROR, "Unable to open '$LocalPathName' for writing: $!");
  return undef;
}

sub GetFileToString($$)
{
  my ($self, $ServerPathName) = @_;
  debug("GetFile $self->{agenthost} $ServerPathName -> String\n");

  return $self->_GetFileOrString($ServerPathName, undef, undef);
}

$RUN_DNT = 1;

sub Run($$$;$$$)
{
  my ($self, $Argv, $Flags, $ServerInPath, $ServerOutPath, $ServerErrPath) = @_;
  debug("Run $self->{agenthost} '", join("' '", @$Argv), "'\n");

  if (!$self->_StartRPC($RPC_RUN) or
      !$self->_SendListSize(4 + @$Argv) or
      !$self->_SendUInt32($Flags) or
      !$self->_SendString($ServerInPath || "") or
      !$self->_SendString($ServerOutPath || "") or
      !$self->_SendString($ServerErrPath || ""))
  {
    return undef;
  }
  foreach my $Arg (@$Argv)
  {
      return undef if (!$self->_SendString($Arg));
  }

  # Get the reply
  return $self->_RecvList('Q');
}

sub Wait($$)
{
  my ($self, $Pid) = @_;
  debug("Wait $Pid\n");

  # Send the command
  if (!$self->_StartRPC($RPC_WAIT) or
      !$self->_SendListSize(1) or
      !$self->_SendUInt64($Pid))
  {
    return undef;
  }

  # Get the reply
  return $self->_RecvList('I');
}

sub Rm($@)
{
  my $self = shift @_;
  debug("Rm\n");

  # Send the command
  if (!$self->_StartRPC($RPC_RM) or
      !$self->_SendListSize(scalar(@_)))
  {
    return $self->GetLastError();
  }
  foreach my $Filename (@_)
  {
    return $self->GetLastError() if (!$self->_SendString($Filename));
  }

  # Get the reply
  return $self->_RecvErrorList();
}

1;
