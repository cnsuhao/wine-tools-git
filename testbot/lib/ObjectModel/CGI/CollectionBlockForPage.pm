# Collection block for list pages
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

ObjectModel::CGI::CollectionBlockForPage - Collection block for list pages

=cut

package ObjectModel::CGI::CollectionBlockForPage;

use ObjectModel::CGI::CollectionBlock;

use vars qw(@ISA @EXPORT);

require Exporter;
@ISA = qw(ObjectModel::CGI::CollectionBlock Exporter);

sub CallGenerateFormStart
{
  my $self = shift;

  $self->{EnclosingPage}->GenerateFormStart($self);
}

sub CallGenerateFormEnd
{
  my $self = shift;

  $self->{EnclosingPage}->GenerateFormEnd($self);
}

sub CallGenerateHeaderRow
{
  my $self = shift;

  $self->{EnclosingPage}->GenerateHeaderRow($self, @_);
}

sub CallGenerateDataRow
{
  my $self = shift;

  $self->{EnclosingPage}->GenerateDataRow($self, @_);
}

sub CallGenerateDataCell
{
  my $self = shift;

  return $self->{EnclosingPage}->GenerateDataCell($self, @_);
}

sub CallGetDetailsPage
{
  my $self = shift;

  return $self->{EnclosingPage}->GetDetailsPage($self, @_);
}

sub CallGetItemActions
{
  my $self = shift;

  return $self->{EnclosingPage}->GetItemActions($self, @_);
}

sub CallGetActions
{
  my $self = shift;

  return $self->{EnclosingPage}->GetActions($self, @_);
}

sub CallDisplayProperty
{
  my $self = shift;

  return $self->{EnclosingPage}->DisplayProperty($self, @_);
}

sub CallGetDisplayValue
{
  my $self = shift;

  return $self->{EnclosingPage}->GetDisplayValue($self, @_);
}

sub CallOnItemAction
{
  my $self = shift;

  return $self->{EnclosingPage}->OnItemAction($self, @_);
}

sub CallSortKeys
{
  my $self = shift;

  return $self->{EnclosingPage}->SortKeys($self, @_);
}

1;
