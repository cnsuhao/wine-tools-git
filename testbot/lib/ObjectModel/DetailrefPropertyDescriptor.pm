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

package ObjectModel::DetailrefPropertyDescriptor;

=head1 NAME

ObjectModel::DetailrefPropertyDescriptor - A reference to a collection of related objects

=cut

use vars qw(@ISA @EXPORT);

require Exporter;
@ISA = qw(ObjectModel::PropertyDescriptor Exporter);
@EXPORT = qw(&CreateDetailrefPropertyDescriptor);

sub _initialize
{
  my $self = shift;
  my $Creator = shift;

  $self->{Class} = "Detailref";
  $self->{Creator} = $Creator;

  $self->SUPER::_initialize(@_);
}

sub GetColNames
{
  return [];
}

sub GetCreator
{
  my $self = shift;

  return $self->{Creator};
}

sub ValidateValue
{
  return undef;
}

sub CreateDetailrefPropertyDescriptor
{
  return ObjectModel::DetailrefPropertyDescriptor->new(@_);
}

1;
