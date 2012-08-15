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

use VMware::Vix::API::Constants;

# Set to "1" if you have a valid SSL certificate, set to "!1" if you don't
$WineTestBot::Config::UseSSL = 1;

# With vCenter Server, ESX/ESXi hosts, and VMware Server 2.0, use
# VIX_SERVICEPROVIDER_VMWARE_VI_SERVER. With VMware Workstation, use
# VIX_SERVICEPROVIDER_VMWARE_WORKSTATION. With VMware Server 1.0.x, use
# VIX_SERVICEPROVIDER_VMWARE_SERVER. 
$WineTestBot::Config::VixHostType = undef;

# Username for authentication on the host. With VMware Workstation and VMware
# Server 1.0.x, use undef to authenticate as the current user on local host.
# With vCenter Server, ESX/ESXi hosts, and VMware Server 2.0, you must use a
# valid login. 
$WineTestBot::Config::VixHostUsername = undef;

# Password for authentication on the host. With VMware Workstation and VMware
# Server 1.0.x, use undef to authenticate as the current user on local host.
# With vCenter Server, ESX/ESXi hosts, and VMware Server 2.0, you must use a
# valid login. 
$WineTestBot::Config::VixHostPassword = undef;

# The name of a user account on the guest operating system.
$WineTestBot::Config::VixGuestUsername = undef;

# The password of the account on the guest operating system.
$WineTestBot::Config::VixGuestPassword = undef;

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

1;
