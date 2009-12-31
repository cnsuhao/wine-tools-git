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

use ObjectModel::DBIBackEnd;

use vars qw (@ISA @EXPORT @EXPORT_OK $UseSSL $LogDir $DataDir $BinDir
             $VixHostType $VixHostName $VixHostUsername $VixHostPassword
             $VixGuestUsername $VixGuestPassword $DbDataSource $DbUsername
             $DbPassword $MaxRevertingVMs $MaxRunningVMs $SleepAfterRevert
             $AdminEMail $RobotEMail $SuiteTimeout $SingleTimeout
             $BuildTimeout $OverheadTimeout);

require Exporter;
@ISA = qw(Exporter);
@EXPORT = qw($UseSSL $LogDir $DataDir $BinDir $VixHostType $VixHostName
             $VixHostUsername $VixHostPassword $VixGuestUsername
             $VixGuestPassword $MaxRevertingVMs $MaxRunningVMs
             $SleepAfterRevert $AdminEMail $RobotEMail $SuiteTimeout
             $SingleTimeout $BuildTimeout $OverheadTimeout); 
@EXPORT_OK = qw($DbDataSource $DbUsername $DbPassword);

$LogDir = "/var/log/winetestbot";
$DataDir = "/var/lib/winetestbot";
$BinDir = "/usr/lib/winetestbot/bin";

$MaxRevertingVMs = 1;
$MaxRunningVMs = 2;
$SleepAfterRevert = 30;

$SuiteTimeout = 30 * 60;
$SingleTimeout = 5 * 60;
$BuildTimeout = 5 * 60;
$OverheadTimeout = 3 * 60;

eval 'require "WineTestBot/ConfigLocal.pl";';
if ($@)
{
  print STDERR "Please create a valid lib/WineTestBot/ConfigLocal.pl, use " .
               "lib/WineTestBot/ConfigLocalTemplate.pl as template\n";
  exit;
}

ObjectModel::DBIBackEnd->UseDBIBackEnd($DbDataSource, $DbUsername, $DbPassword, 
                                       { RaiseError => 1 });

umask 002;

1;
