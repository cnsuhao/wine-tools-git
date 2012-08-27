# Role of a user collection and items
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

WineTestBot::UserRoles - User role collection

=cut

package WineTestBot::UserRole;

use WineTestBot::WineTestBotObjects;

use vars qw(@ISA @EXPORT);

require Exporter;
@ISA = qw(WineTestBot::WineTestBotItem Exporter);

package WineTestBot::UserRoles;

use ObjectModel::ItemrefPropertyDescriptor;
use ObjectModel::PropertyDescriptor;
use WineTestBot::Roles;
use WineTestBot::WineTestBotObjects;

use vars qw(@ISA @EXPORT @PropertyDescriptors);

require Exporter;
@ISA = qw(WineTestBot::WineTestBotCollection Exporter);
@EXPORT = qw(&CreateUserRoles);

BEGIN
{
  $PropertyDescriptors[0] =
    CreateItemrefPropertyDescriptor("Role", "Role", 1,  1, \&CreateRoles, ["RoleName"]);

}

sub CreateItem
{
  my $self = shift;

  return WineTestBot::UserRole->new($self);
}

sub CreateUserRoles
{
  my $User = shift;

  return WineTestBot::UserRoles->new("UserRoles", "UserRoles", "UserRole",
                                     \@PropertyDescriptors, $User);
}

1;
