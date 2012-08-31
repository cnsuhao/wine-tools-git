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

=head1 NAME

ObjectModel::EnumPropertyDescriptor - Defines a property that can only take
a set of values.

=cut

package ObjectModel::EnumPropertyDescriptor;

use ObjectModel::PropertyDescriptor;

use vars qw(@ISA @EXPORT);

require Exporter;
@ISA = qw(ObjectModel::PropertyDescriptor Exporter);
@EXPORT = qw(&CreateEnumPropertyDescriptor);

sub _initialize
{
  my $self = shift;
  my $Values = shift;

  $self->{Class} = "Enum";
  $self->{Values} = $Values;

  $self->SUPER::_initialize(@_);
}

sub GetValues
{
  my $self = shift;

  return $self->{Values};
}

sub GetColNames
{
  my $self = shift;

  return [$self->{Name}];
}

sub ValidateValue
{
  my $self = shift;
  my ($Value, $IsNew) = @_;

  if ($self->GetIsRequired())
  {
    if (!$IsNew && (!defined($Value) || $Value eq ""))
    {
      return $self->GetDisplayName() .  ": Must be entered";
    }
  }

  foreach my $V (@{$self->{Values}})
  {
      return undef if ($V eq $Value);
  }
  return $self->GetDisplayName() . ": Is not valid";
}

sub CreateEnumPropertyDescriptor
{
  return ObjectModel::EnumPropertyDescriptor->new(@_);
}

1;
