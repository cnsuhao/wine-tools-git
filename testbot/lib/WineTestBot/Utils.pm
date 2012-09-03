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

package WineTestBot::Utils;

=head1 NAME

WineTestBot::Utils - Utility functions

=cut

use WineTestBot::Config;

use vars qw (@ISA @EXPORT);

require Exporter;
@ISA = qw(Exporter);
@EXPORT = qw(&MakeSecureURL &SecureConnection &GenerateRandomString
             &BuildEMailRecipient);

sub MakeSecureURL
{
  my $URL = shift;

  my $Protocol = "http";
  if ($UseSSL || SecureConnection())
  {
    $Protocol .= "s";
  }

  return $Protocol . "://" . $ENV{"HTTP_HOST"} . $URL;
}

sub SecureConnection
{
  return defined($ENV{"HTTPS"}) && $ENV{"HTTPS"} eq "on";
}

sub GenerateRandomString
{
  my $Len = $_[0];

  my $RandomString = "";
  while (length($RandomString) < $Len)
  {
    my $Part = "0000" . sprintf("%lx", int(rand(2 ** 16)));
    $RandomString .= substr($Part, -4);
  }

  return substr($RandomString, 0, $Len);
}

sub DateTimeToString
{
  my $Time = $_[0];

#  my ($Sec, $Min, $Hour, $MDay, $Mon, $Year, $WDay, $YDay, $IsDst) = localtime($Time);
  return strftime("%Y/%m/%d %H:%M:%S", localtime($Time));
}

sub BuildEMailRecipient
{
  my ($EMailAddress, $Name) = @_;

  if (! defined($EMailAddress))
  {
    return undef;
  }
  my $Recipient = "<" . $EMailAddress . ">";
  if ($Name)
  {
    $Recipient .= " ($Name)";
  }

  return $Recipient;
}


1;
