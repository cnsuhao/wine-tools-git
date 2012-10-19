# WineTestBot configuration
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

use strict;

# Set to "1" if you have a valid SSL certificate, set to "!1" if you don't
$WineTestBot::Config::UseSSL = 1;

# The DBI data source name of the database (e.g. "DBI:mysql:winetestbot")
$WineTestBot::Config::DbDataSource = "DBI:mysql:winetestbot";

# The name of the database account
$WineTestBot::Config::DbUsername = "winetestbot";

# The password of the database account
$WineTestBot::Config::DbPassword = "";

# Email address of the WineTestBot administrator
$WineTestBot::Config::AdminEMail = undef;

# From address of mails sent by WineTestBot to users
$WineTestBot::Config::RobotEMail = undef;

# If set, sends the results to the specified email address instead of the
# patch author. Set it to undef once your WineTestBot installation works and
# can provide useful results to Wine developers.
$WineTestBot::Config::WinePatchToOverride = $WineTestBot::Config::AdminEMail;

# If set, CC the results to the specified email address, for instance the
# wine-devel mailing list.
$WineTestBot::Config::WinePatchCc = "";

# Email address to send the results to for integration with the Wine Patches
# web site
$WineTestBot::Config::PatchResultsEMail = undef;

# Host name of the web interface
$WineTestBot::Config::WebHostName = undef;

# Prefix of the tag used for sending winetest reports
$WineTestBot::Config::TagPrefix = undef;

# If you want to use LDAP authentication instead of built-in, you'll have
# to define all 6 LDAP settings: $LDAPServer, $LDAPBindDN, $LDAPSearchBase,
# $LDAPSearchFilter, $LDAPRealNameAttribute and $LDAPEMail
# LDAP server, can be in URL format like "ldaps://ldap.example.com"
$WineTestBot::Config::LDAPServer = undef;

# DN used to bind to LDAP, %USERNAME% is replaced by the login name provided
# by the user. E.g. "%USERNAME%\@example.com" (remember to escape the @)
$WineTestBot::Config::LDAPBindDN = undef;

# DN used as search base to obtain user information, e.g.
# "CN=Users,DC=example,DC=com"
$WineTestBot::Config::LDAPSearchBase = undef;

# Filter expression, %USERNAME% is replaced by login name, e.g.
# "(sAMAccountName=%USERNAME%)"
$WineTestBot::Config::LDAPSearchFilter = undef;

# LDAP attribute for a users real name
$WineTestBot::Config::LDAPRealNameAttribute = undef;

# LDAP attribute for a users email address
$WineTestBot::Config::LDAPEMailAttribute = undef;

# The port the VM agents are listening on
$WineTestBot::Config::AgentPort = undef;

1;
