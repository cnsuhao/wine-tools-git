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

package WineTestBot::Config;

=head1 NAME

WineTestBot::Config - Site-independent configuration settings

=cut

use vars qw (@ISA @EXPORT @EXPORT_OK $UseSSL $LogDir $DataDir $BinDir
             $DbDataSource $DbUsername $DbPassword $MaxRevertingVMs
             $MaxRunningVMs $MaxNonBasePoweredOnVms $SleepAfterRevert
             $WaitForToolsInVM $AdminEMail $RobotEMail $WinePatchToOverride
             $WinePatchCc $SuiteTimeout $SingleTimeout
             $BuildTimeout $ReconfigTimeout $OverheadTimeout $TagPrefix
             $ProjectName $PatchesMailingList $PatchResultsEMail $LDAPServer
             $LDAPBindDN $LDAPSearchBase $LDAPSearchFilter
             $LDAPRealNameAttribute $LDAPEMailAttribute $AgentPort
             $JobPurgeDays $JobArchiveDays $WebHostName);

require Exporter;
@ISA = qw(Exporter);
@EXPORT = qw($UseSSL $LogDir $DataDir $BinDir
             $MaxRevertingVMs $MaxRunningVMs $MaxNonBasePoweredOnVms
             $SleepAfterRevert $WaitForToolsInVM $AdminEMail $RobotEMail
             $WinePatchToOverride $WinePatchCc $SuiteTimeout
             $SingleTimeout $BuildTimeout $ReconfigTimeout $OverheadTimeout
             $TagPrefix $ProjectName $PatchesMailingList $PatchResultsEMail
             $LDAPServer $LDAPBindDN $LDAPSearchBase $LDAPSearchFilter
             $LDAPRealNameAttribute $LDAPEMailAttribute $AgentPort
             $JobPurgeDays $JobArchiveDays $WebHostName);
@EXPORT_OK = qw($DbDataSource $DbUsername $DbPassword);

$LogDir = "$::RootDir/var";
$DataDir = "$::RootDir/var";
$BinDir = "$::RootDir/bin";

$MaxRevertingVMs = 1;
$MaxRunningVMs = 2;
$MaxNonBasePoweredOnVms = 2;
$SleepAfterRevert = 30;
$WaitForToolsInVM = 30;

$SuiteTimeout = 30 * 60;
$SingleTimeout = 2 * 60;
$BuildTimeout = 5 * 60;
$ReconfigTimeout = 45 * 60;
$OverheadTimeout = 3 * 60;

$ProjectName = "Wine";
$PatchesMailingList = "wine-patches";

$LDAPServer = undef;
$LDAPBindDN = undef;
$LDAPSearchBase = undef;
$LDAPSearchFilter = undef;
$LDAPRealNameAttribute = undef;
$LDAPEMailAttribute = undef;

$JobPurgeDays = 7;
$JobArchiveDays = 0;

if (!$::BuildEnv)
{
  $::BuildEnv = 0;
  eval 'require "$::RootDir/ConfigLocal.pl";';
  if ($@)
  {
    print STDERR "Please create a valid $::RootDir/ConfigLocal.pl, " .
        "use $::RootDir/lib/WineTestBot/ConfigLocalTemplate.pl as template\n";
    exit;
  }

  require ObjectModel::DBIBackEnd;
  ObjectModel::DBIBackEnd->UseDBIBackEnd('WineTestBot', $DbDataSource,
                                         $DbUsername, $DbPassword,
                                         { RaiseError => 1 });
}

umask 002;

1;
