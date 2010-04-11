# Incomplete series part collection and items
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

WineTestBot::PendingPatches - Incomplete series part collection

=cut

package WineTestBot::PendingPatch;
use ObjectModel::Item;

use vars qw(@ISA @EXPORT);

require Exporter;
@ISA = qw(ObjectModel::Item Exporter);

package WineTestBot::PendingPatches;

use ObjectModel::BasicPropertyDescriptor;
use ObjectModel::Collection;
use ObjectModel::ItemrefPropertyDescriptor;
use ObjectModel::PropertyDescriptor;
use WineTestBot::Patches;

use vars qw(@ISA @EXPORT @PropertyDescriptors);

require Exporter;
@ISA = qw(ObjectModel::Collection Exporter);
@EXPORT = qw(&CreatePendingPatches);

BEGIN
{
  $PropertyDescriptors[0] =
    CreateBasicPropertyDescriptor("No", "Part no", 1, 1, "N", 2);
  $PropertyDescriptors[1] =
    CreateItemrefPropertyDescriptor("Patch", "Submitted via patch", !1, 1, \&WineTestBot::Patches::CreatePatches, ["PatchId"]);
}

sub CreateItem
{
  my $self = shift;

  return WineTestBot::PendingPatch->new($self);
}

sub CreatePendingPatches
{
  my $PendingPatchSeries = shift;

  return WineTestBot::PendingPatches->new("PendingPatches", "PendingPatches", "PendingPatch", \@WineTestBot::PendingPatches::PropertyDescriptors, $PendingPatchSeries);
}

1;
