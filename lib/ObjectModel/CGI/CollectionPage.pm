# Base class for list pages
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

ObjectModel::CGI::CollectionPage - Base class for list pages

=cut

package ObjectModel::CGI::CollectionPage;

use ObjectModel::CGI::CollectionBlockForPage;
use ObjectModel::CGI::Page;

use vars qw(@ISA @EXPORT);

require Exporter;
@ISA = qw(ObjectModel::CGI::Page Exporter);

sub _initialize
{
  my $self = shift;
  my ($Request, $RequiredRole, $Collection) = @_;

  $self->{Collection} = $Collection;

  $self->SUPER::_initialize($Request, $RequiredRole);
}

sub GeneratePage
{
  my $self = shift;

  if ($self->GetParam("Action"))
  {
    my $CollectionBlock = $self->CreateCollectionBlock($self->{Collection});
    $self->{ActionPerformed} = $self->OnAction($CollectionBlock,
                                               $self->GetParam("Action"));
  }

  $self->SUPER::GeneratePage(@_);
}

sub GenerateTitle
{
  my $self = shift;

  my $Title = $self->GetTitle();
  if ($Title)
  {
    print "<h1>$Title</h1>\n";
  }
}

sub GenerateBody
{
  my $self = shift;

  print "<div class='CollectionPageBody'>\n";
  $self->GenerateTitle();
  my $CollectionBlock = $self->CreateCollectionBlock($self->{Collection});
  $CollectionBlock->GenerateList();
  print "</div>\n";
}

sub GenerateFormStart
{
  my $self = shift;
  my $CollectionBlock = shift;

  $CollectionBlock->GenerateFormStart(@_);
}

sub GenerateFormEnd
{
  my $self = shift;
  my $CollectionBlock = shift;

  $CollectionBlock->GenerateFormEnd(@_);
}

sub GenerateHeaderRow
{
  my $self = shift;
  my $CollectionBlock = shift;

  $CollectionBlock->GenerateHeaderRow(@_);
}

sub GenerateDataRow
{
  my $self = shift;
  my $CollectionBlock = shift;

  $CollectionBlock->GenerateDataRow(@_);
}

sub GenerateDataCell
{
  my $self = shift;
  my $CollectionBlock = shift;

  $CollectionBlock->GenerateDataCell(@_);
}

sub CreateCollectionBlock
{
  my $self = shift;
  my $Collection = $_[0];

  return ObjectModel::CGI::CollectionBlockForPage->new($Collection, $self);
}

sub GetDetailsPage
{
  my $self = shift;
  my $CollectionBlock = shift;

  return $CollectionBlock->GetDetailsPage(@_);
}

sub GetTitle
{
  my $self = shift;
  my $CollectionBlock = shift;

  return ucfirst($self->{Collection}->GetCollectionName());
}

sub GetItemActions
{
  my $self = shift;
  my $CollectionBlock = shift;

  return $CollectionBlock->GetItemActions(@_);
}

sub GetActions
{
  my $self = shift;
  my $CollectionBlock = shift;

  return $CollectionBlock->GetActions(@_);
}

sub DisplayProperty
{
  my $self = shift;
  my $CollectionBlock = shift;

  return $CollectionBlock->DisplayProperty(@_);
}

sub OnAction
{
  my $self = shift;
  my $CollectionBlock = shift;

  $CollectionBlock->OnAction(@_);
}

sub OnItemAction
{
  my $self = shift;
  my $CollectionBlock = shift;

  return $CollectionBlock->OnItemAction(@_);
}

sub GetDisplayValue
{
  my $self = shift;
  my $CollectionBlock = shift;

  return $CollectionBlock->GetDisplayValue(@_);
}

sub SortKeys
{
  my $self = shift;
  my $CollectionBlock = shift;

  return $CollectionBlock->SortKeys(@_);
}

1;
