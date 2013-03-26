# VM details page
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

package VMDetailsPage;

use ObjectModel::CGI::ItemPage;
use WineTestBot::VMs;

@VMDetailsPage::ISA = qw(ObjectModel::CGI::ItemPage);

sub _initialize
{
  my $self = shift;

  $self->SUPER::_initialize(@_, CreateVMs());
}

sub DisplayProperty
{
  my $self = shift;
  my $PropertyDescriptor = $_[0];

  return "" if ($PropertyDescriptor->GetName() eq "ChildPid");
  return $self->SUPER::DisplayProperty(@_);
}

package main;

my $Request = shift;

my $VMDetailsPage = VMDetailsPage->new($Request, "admin");
$VMDetailsPage->GeneratePage();
