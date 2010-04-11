# Incomplete patch series collection and items
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

WineTestBot::PendingPatchSeriesCollection - PendingPatchSeries collection

=cut


package WineTestBot::PendingPatchSeries;

use ObjectModel::Item;
use WineTestBot::Config;
use WineTestBot::Patches;
use WineTestBot::Utils;

use vars qw(@ISA @EXPORT);

require Exporter;
@ISA = qw(ObjectModel::Item Exporter);

sub CheckComplete
{
  my $self = shift;

  my $Parts = $self->Parts;
  my $MissingPart = !1;
  for (my $PartNo = 1; $PartNo <= $self->TotalParts && ! $MissingPart;
       $PartNo++)
  {
    $MissingPart = ! defined($Parts->GetItem($PartNo));
  }

  return ! $MissingPart;
}

sub Submit
{
  my $self = shift;
  my $FinalPatch = $_[0];

  my $CombinedFileName = "$DataDir/staging/" . GenerateRandomString(32) .
                         "_patch";
  while (-e $CombinedFileName)
  {
    $CombinedFileName = "$DataDir/staging/" . GenerateRandomString(32) .
                        "_patch";
  }

  if (! open(COMBINED, ">$CombinedFileName"))
  {
    return "Can't create combined patch file";
  }

  my $Parts = $self->Parts;
  for (my $PartNo = 1; $PartNo <= $self->TotalParts; $PartNo++)
  {
    my $Part = $Parts->GetItem($PartNo);
    if (defined($Part))
    {
      if (open(PART, "<$DataDir/patches/" . $Part->Patch->Id))
      {
        print COMBINED <PART>;
        close(PART);
      }
    }
  }

  close(COMBINED);

  my $ErrMessage = $FinalPatch->Submit($CombinedFileName, 1);
  unlink($CombinedFileName);

  return $ErrMessage;
}

package WineTestBot::PendingPatchSeriesCollection;

use ObjectModel::BasicPropertyDescriptor;
use ObjectModel::Collection;
use ObjectModel::DetailrefPropertyDescriptor;
use WineTestBot::Config;
use WineTestBot::PendingPatches;
use WineTestBot::Patches;
use WineTestBot::Utils;

use vars qw(@ISA @EXPORT @PropertyDescriptors);

require Exporter;
@ISA = qw(ObjectModel::Collection Exporter);
@EXPORT = qw(&CreatePendingPatchSeriesCollection);

my @PropertyDescriptors;

BEGIN
{
  $PropertyDescriptors[0] =
    CreateBasicPropertyDescriptor("EMail", "EMail of series author", 1, 1, "A", 40);
  $PropertyDescriptors[1] =
    CreateBasicPropertyDescriptor("TotalParts", "Expected number of parts in series", !1, 1, "N", 2);
  $PropertyDescriptors[2] =
    CreateDetailrefPropertyDescriptor("Parts", "Parts received so far", !1, !1, \&CreatePendingPatches);
}

sub CreateItem
{
  my $self = shift;

  return WineTestBot::PendingPatchSeries->new($self);
}

sub NewSubmission
{
  my $self = shift;

  my $Patch = $_[0];
  if (! defined($Patch->FromEMail))
  {
    $Patch->Disposition("Unable to determine series author");
    return undef;
  }

  my $Series = $self->GetItem($Patch->FromEMail);
  if (! defined($Series))
  {
    $Series = $self->Add();
    $Series->EMail($Patch->FromEMail);
    $Series->TotalParts(0);
  }

  my $Subject = $Patch->Subject;
  $Subject =~ m/(\d+)\/(\d+)/;
  my $PartNo = int($1);
  my $MaxPartNo = int($2);
  if ($MaxPartNo < $PartNo)
  {
    $MaxPartNo = $PartNo;
  }
  if ($Series->TotalParts < $MaxPartNo)
  {
    $Series->TotalParts($MaxPartNo);
  }

  my $Parts = $Series->Parts;
  my $Part = $Parts->GetItem($PartNo);
  if (! defined($Part))
  {
    $Part = $Parts->Add();
    $Part->No($PartNo);
  }

  $Part->Patch($Patch);

  my ($ErrKey, $ErrProperty, $ErrMessage) = $self->Save();
  if (defined($ErrMessage))
  {
    $Patch->Disposition("Error occurred during series processing");
  }

  if (! $Series->CheckComplete())
#if (1)
  {
    $Patch->Disposition("Series not complete yet");
  }
  else
  {
    $ErrMessage = $Series->Submit($Patch);
    $self->DeleteItem($Series);
  }

  return $ErrMessage;
}

sub CheckForCompleteSeries
{
  my $self = shift;

  my $ErrMessage;
  foreach my $SeriesKey (@{$self->GetKeys()})
  {
    my $Series = $self->GetItem($SeriesKey);
    if ($Series->CheckComplete())
    {
      my $Patch = $Series->Parts->GetItem($Series->TotalParts)->Patch;
      my $SeriesErrMessage = $Series->Submit($Patch);
      if (defined($SeriesErrMessage))
      {
        if (! defined($ErrMessage))
        {
          $ErrMessage = $SeriesErrMessage;
        }
      }
      else
      {
        $Patch->Save();
      }
      $self->DeleteItem($Series);
    }
  }

  return $ErrMessage;
}

sub CreatePendingPatchSeriesCollection
{
  return WineTestBot::PendingPatchSeriesCollection->new("PendingPatchSeries", "PendingPatchSeriesCollection", "PendingPatchSeries", \@PropertyDescriptors);
}

1;
