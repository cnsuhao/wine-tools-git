# Item property description
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

ObjectModel::PropertyDescriptor - Base class for item property descriptions

=cut

package ObjectModel::ItemrefPropertyDescriptor;

use vars qw(@ISA @EXPORT);

require Exporter;
@ISA = qw(ObjectModel::PropertyDescriptor Exporter);
@EXPORT = qw(&CreateItemrefPropertyDescriptor);

sub _initialize
{
  my $self = shift;
  my $Creator = shift;
  my $ColNames = shift;

  $self->{Class} = "Itemref";
  $self->{Creator} = $Creator;
  $self->{ColNames} = $ColNames;

  $self->SUPER::_initialize(@_);
}

sub GetCreator
{
  my $self = shift;

  return $self->{Creator};
}

sub GetColNames
{
  my $self = shift;

  return $self->{ColNames};
}

sub ValidateValue
{
  my $self = shift;
  my ($Value, $IsNew) = @_;

  if ($self->GetIsRequired() && ! defined($Value))
  {
    return $self->GetDisplayName() .  ": Must be entered";
  }

  return undef;
}

sub CreateItemrefPropertyDescriptor
{
  return ObjectModel::ItemrefPropertyDescriptor->new(@_);
}

1;
