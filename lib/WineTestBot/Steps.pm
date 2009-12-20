# Job step collection and items
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

WineTestBot::Steps - Job step collection

=cut

package WineTestBot::Step;

use File::Copy;
use ObjectModel::Item;
use WineTestBot::Config;

use vars qw(@ISA @EXPORT);

require Exporter;
@ISA = qw(ObjectModel::Item Exporter);

sub InitializeNew
{
  my $self = shift;
  my $Collection = $_[0];

  $self->Status("queued");
  my $Keys = $Collection->GetKeys();
  $self->No(scalar @$Keys + 1);
  $self->InStaging(1);
  $self->DebugLevel(1);
  $self->ReportSuccessfulTests(!1);

  $self->SUPER::InitializeNew(@_);
}

sub HandleStaging
{
  my $self = shift;
  my $JobKey = $_[0];

  if (! $self->InStaging)
  {
    return undef;
  }

  my $FileName = $self->FileName;
  if (! ($FileName =~ m/^([\da-fA-F]+) (.*)$/))
  {
    return "Can't split staging file name";
  }
  $FileName = $2;
  my $StagingFileName = "$DataDir/staging/$1_$FileName";
  my $FinalFileName = "$DataDir/jobs/$JobKey/" . $self->GetKey() .
                      "/$FileName";
  mkdir "$DataDir/jobs/$JobKey";
  mkdir "$DataDir/jobs/$JobKey/" . $self->GetKey();
  if (! copy($StagingFileName, $FinalFileName))
  {
    return "Can't copy file from staging area: $!";
  }
  unlink($StagingFileName);

  $self->FileName($FileName);
  $self->InStaging(!1);
  my ($ErrProperty, $ErrMessage) = $self->Save();

  return $ErrMessage;
}

package WineTestBot::Steps;

use ObjectModel::BasicPropertyDescriptor;
use ObjectModel::Collection;
use ObjectModel::DetailrefPropertyDescriptor;
use ObjectModel::PropertyDescriptor;
use WineTestBot::Tasks;

use vars qw(@ISA @EXPORT @PropertyDescriptors);

require Exporter;
@ISA = qw(ObjectModel::Collection Exporter);
@EXPORT = qw(&CreateSteps);

BEGIN
{
  $PropertyDescriptors[0] =
    CreateBasicPropertyDescriptor("No",     "Step no",  1,  1, "N", 2);
  $PropertyDescriptors[1] =
    CreateBasicPropertyDescriptor("Status", "Status",  !1,  1, "A", 9);
  $PropertyDescriptors[2] =
    CreateBasicPropertyDescriptor("FileName", "File name",  !1,  1, "A", 64);
  $PropertyDescriptors[3] =
    CreateBasicPropertyDescriptor("InStaging", "File is in staging area", !1, 1, "B", 1);
  $PropertyDescriptors[4] =
    CreateBasicPropertyDescriptor("DebugLevel", "Debug level (WINETEST_DEBUG)", !1, 1, "N", 2);
  $PropertyDescriptors[5] =
    CreateBasicPropertyDescriptor("ReportSuccessfulTests", "Report successfull tests (WINETEST_REPORT_SUCCESS)", !1, 1, "B", 1);
  $PropertyDescriptors[6] =
    CreateDetailrefPropertyDescriptor("Tasks", "Tasks", !1, !1, \&CreateTasks);
}

sub CreateItem
{
  my $self = shift;

  return WineTestBot::Step->new($self);
}

sub CreateSteps
{
  my $Job = shift;

  return WineTestBot::Steps->new("Steps", "Steps", "Step",
                                 \@WineTestBot::Steps::PropertyDescriptors,
                                 $Job);
}

1;
