# Patch list page
#
# Copyright 2010 Ge van Geldorp
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

package PatchesListPage;

use URI::Escape;
use ObjectModel::PropertyDescriptor;
use ObjectModel::CGI::CollectionPage;
use WineTestBot::Patches;

@PatchesListPage::ISA = qw(ObjectModel::CGI::CollectionPage);

sub _initialize
{
  my $self = shift;

  $self->SUPER::_initialize(@_, CreatePatches());
}

sub SortKeys
{
  my $self = shift;
  my ($CollectionBlock, $Keys) = @_;

  my @SortedKeys = sort { $b <=> $a } @$Keys;
  return \@SortedKeys;
}

sub DisplayProperty
{
  my $self = shift;
  my ($CollectionBlock, $PropertyDescriptor) = @_;

  my $PropertyName = $PropertyDescriptor->GetName();

  return $PropertyName eq "Received" || $PropertyName eq "Disposition" ||
         $PropertyName eq "FromName" || $PropertyName eq "Subject";
}

sub GetItemActions
{
  my $self = shift;
  my $CollectionBlock = shift;

  return [];
}

sub GetActions
{
  my $self = shift;
  my $CollectionBlock = shift;

  return [];
}

sub GeneratePage
{
  my $self = shift;

  $self->{Request}->headers_out->add("Refresh", "60");

  $self->SUPER::GeneratePage(@_);
}

sub GenerateDataCell
{
  my $self = shift;
  my ($CollectionBlock, $Item, $PropertyDescriptor, $DetailsPage) = @_;

  my $PropertyName = $PropertyDescriptor->GetName();
  if ($PropertyName eq "Disposition" and $Item->Disposition =~ /job ([0-9]+)$/)
  {
    my $JobId = $1;
    my $URI = "/JobDetails.pl?Key=" . uri_escape($JobId);
    print "<td><a href='" . $self->escapeHTML($URI) . "'>" .
          "Job " . $self->escapeHTML($JobId) . "</a></td>\n";
  }
  else
  {
    $self->SUPER::GenerateDataCell(@_);
  }
}

package main;

my $Request = shift;

my $PatchesListPage = PatchesListPage->new($Request, "");
$PatchesListPage->GeneratePage();
