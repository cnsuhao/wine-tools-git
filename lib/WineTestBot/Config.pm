# WineTestBot configuration
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

WineTestBot::Config - Configuration settings

=cut

package WineTestBot::Config;

use vars qw (@ISA @EXPORT $UseSSL $LogDir $DataDir $BinDir $VixHostName
             $VixHostUsername $VixHostPassword $VixGuestUsername
             $VixGuestPassword $MaxRevertingVMs $MaxRunningVMs
             $SleepAfterRevert $AdminEMail $SuiteTimeout $SingleTimeout
             $OverheadTimeout);

require Exporter;
@ISA = qw(Exporter);
@EXPORT = qw($UseSSL $LogDir $DataDir $BinDir $VixHostName $VixHostUsername
             $VixHostPassword $VixGuestUsername $VixGuestPassword
             $MaxRevertingVMs $MaxRunningVMs $SleepAfterRevert $AdminEMail
             $SuiteTimeout $SingleTimeout $OverheadTimeout); 

$UseSSL = 1;

$LogDir = "/var/log/winetestbot";
$DataDir = "/var/lib/winetestbot";
$BinDir = "/usr/lib/winetestbot/bin";

die "Please set connection details in WineTestBot/Config.pm";
$VixHostName = "";
$VixHostUsername = "";
$VixHostPassword = "";
$VixGuestUsername = "";
$VixGuestPassword = "";

$MaxRevertingVMs = 3;
$MaxRunningVMs = 4;
$SleepAfterRevert = 30;

$AdminEMail = "";

$SuiteTimeout = 30 * 60;
$SingleTimeout = 5 * 60;
$OverheadTimeout = 3 * 60;

1;
