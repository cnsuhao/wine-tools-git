#!/usr/bin/perl -Tw
#
# Ping WineTestBot engine to see if it is alive
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
use lib "/usr/lib/winetestbot/lib";

use WineTestBot::Config;
use WineTestBot::Engine::Notify;

$ENV{PATH} = "/sbin:/usr/sbin:/usr/bin:/bin";
delete $ENV{ENV};

if (! PingEngine())
{
  system "service winetestbot restart > /dev/null";
  sleep 5;
  
  open (SENDMAIL, "|/usr/sbin/sendmail -oi -t -odq");
  print SENDMAIL <<"EOF";
From: <$RobotEMail> (Marvin)
To: $AdminEMail
Subject: WineTestBot engine died

EOF
  if (PingEngine())
  {
    print SENDMAIL "The engine was restarted successfully\n";
  }
  else
  {
    print SENDMAIL "Unable to restart the engine\n";
  }
  close(SENDMAIL);
}
