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

WineTestBot::PendingPatchSets - PendingPatchSet collection

=cut


package WineTestBot::PendingPatchSet;

use ObjectModel::Item;
use WineTestBot::Config;
use WineTestBot::Patches;
use WineTestBot::Utils;

use vars qw(@ISA @EXPORT);

require Exporter;
@ISA = qw(ObjectModel::Item Exporter);

sub CheckSubsetComplete
{
  my $self = shift;
  my $MaxPart = $_[0];

  my $Parts = $self->Parts;
  my $MissingPart = !1;
  for (my $PartNo = 1; $PartNo <= $MaxPart && ! $MissingPart;
       $PartNo++)
  {
    $MissingPart = ! defined($Parts->GetItem($PartNo));
  }

  return ! $MissingPart;
}

sub CheckComplete
{
  my $self = shift;

  return $self->CheckSubsetComplete($self->TotalParts)
}

sub SubmitSubset
{
  my $self = shift;
  my ($MaxPart, $FinalPatch) = @_;

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
  for (my $PartNo = 1; $PartNo <= $MaxPart; $PartNo++)
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

sub Submit
{
  my $self = shift;
  my $FinalPatch = $_[0];

  return $self->SubmitSubset($self->TotalParts, $FinalPatch);
}

package WineTestBot::PendingPatchSets;

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
@EXPORT = qw(&CreatePendingPatchSets);

my @PropertyDescriptors;

BEGIN
{
  $PropertyDescriptors[0] =
    CreateBasicPropertyDescriptor("EMail", "EMail of series author", 1, 1, "A", 40);
  $PropertyDescriptors[1] =
    CreateBasicPropertyDescriptor("TotalParts", "Expected number of parts in series", 1, 1, "N", 2);
  $PropertyDescriptors[2] =
    CreateDetailrefPropertyDescriptor("Parts", "Parts received so far", !1, !1, \&CreatePendingPatches);
}

sub CreateItem
{
  my $self = shift;

  return WineTestBot::PendingPatchSet->new($self);
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

  my $Subject = $Patch->Subject;
  $Subject =~ s/32\/64//;
  $Subject =~ s/64\/32//;
  $Subject =~ m/(\d+)\/(\d+)/;
  my $PartNo = int($1);
  my $MaxPartNo = int($2);

  my $DummySet = CreatePendingPatchSets()->Add();
  $DummySet->EMail($Patch->FromEMail);
  $DummySet->TotalParts($MaxPartNo);
  my $SetKey = $DummySet->GetKey();
  $DummySet = undef;

  my $Set = $self->GetItem($SetKey);
  if (! defined($Set))
  {
    $Set = $self->Add();
    $Set->EMail($Patch->FromEMail);
    $Set->TotalParts($MaxPartNo);
  }

  my $Parts = $Set->Parts;
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

  if (! $Set->CheckSubsetComplete($PartNo))
  {
    $Patch->Disposition($Patch->AffectsTests ? "Set not complete yet" :
                        "Patch doesn't affect tests");
  }
  else
  {
    my $AllPartsAvailable = 1;
    while ($PartNo <= $Set->TotalParts && $AllPartsAvailable &&
           ! defined($ErrMessage))
    {
      my $Part = $Parts->GetItem($PartNo);
      if (defined($Part))
      {
        if ($Part->Patch->AffectsTests)
        {
          $ErrMessage = $Set->SubmitSubset($PartNo, $Part->Patch);
        }
        else
        {
          $Part->Patch->Disposition("Patch doesn't affect tests");
        }
        my $ErrProperty;
        ($ErrProperty, $ErrMessage) = $Part->Patch->Save();
      }
      else
      {
        $AllPartsAvailable = !1;
      }
      $PartNo++;
    }
    if ($AllPartsAvailable && ! defined($ErrMessage))
    {
      $self->DeleteItem($Set);
    }
  }

  return $ErrMessage;
}

sub CheckForCompleteSet
{
  my $self = shift;

  my $ErrMessage;
  foreach my $SetKey (@{$self->GetKeys()})
  {
    my $Set = $self->GetItem($SetKey);
    if ($Set->CheckComplete())
    {
      my $Patch = $Set->Parts->GetItem($Set->TotalParts)->Patch;
      my $SetErrMessage = $Set->Submit($Patch);
      if (defined($SetErrMessage))
      {
        if (! defined($ErrMessage))
        {
          $ErrMessage = $SetErrMessage;
        }
      }
      else
      {
        $Patch->Save();
      }
      $self->DeleteItem($Set);
    }
  }

  return $ErrMessage;
}

sub CreatePendingPatchSets
{
  return WineTestBot::PendingPatchSets->new("PendingPatchSets", "PendingPatchSets", "PendingPatchSet", \@PropertyDescriptors);
}

1;
