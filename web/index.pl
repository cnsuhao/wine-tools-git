# WineTestBot status page
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

package JobStatusBlock;

use ObjectModel::CGI::CollectionBlock;

use vars qw(@ISA);

@ISA = qw(ObjectModel::CGI::CollectionBlock);

sub SortKeys
{
  my $self = shift;
  my $Keys = $_[0];

  my @SortedKeys = sort { $b <=> $a } @$Keys;
  return \@SortedKeys;
}

sub GetItemActions
{
  return [];
}

sub GetActions
{
  return [];
}

sub DisplayProperty
{
  my $self = shift;

  my $PropertyDescriptor = $_[0];
  if ($PropertyDescriptor->GetName() eq "Patch")
  {
    return !1;
  }

  return $self->SUPER::DisplayProperty(@_);
}

sub GetDisplayValue
{
  my $self = shift;
  my ($Item, $PropertyDescriptor) = @_;

  if ($PropertyDescriptor->GetName() eq "User" &&
      defined($Item->Patch) &&
      $Item->User->GetKey() eq WineTestBot::Users->GetBatchUser()->GetKey() &&
      defined($Item->Patch->FromName))
  {
    return $Item->Patch->FromName;
  }

  return $self->SUPER::GetDisplayValue(@_);
}

package VMStatusBlock;

use ObjectModel::CGI::CollectionBlock;

use vars qw(@ISA);

@ISA = qw(ObjectModel::CGI::CollectionBlock);

sub SortKeys
{
  my $self = shift;
  my $Keys = $_[0];

  return $self->{Collection}->SortKeysBySortOrder($Keys);
}

sub GetItemActions
{
  return [];
}

sub GetActions
{
  return [];
}

sub DisplayProperty
{
  my $self = shift;
  my $PropertyDescriptor = $_[0];

  my $PropertyName = $PropertyDescriptor->GetName();
  return $PropertyName eq "Name" || $PropertyName eq "Type" ||
         $PropertyName eq "Bits" || $PropertyName eq "Status" ||
         $PropertyName eq "Description";
}

sub GetDetailsPage
{
  return undef;
}

package StatusPage;

use ObjectModel::CGI::Page;
use WineTestBot::Config;
use WineTestBot::Engine::Notify;
use WineTestBot::Jobs;
use WineTestBot::VMs;

@StatusPage::ISA = qw(ObjectModel::CGI::Page);

sub _initialize
{
  my $self = shift;

  $self->SUPER::_initialize(@_, CreateJobs());
}

sub OutputDot
{
  my $self = shift;
  my $DotColor = $_[0];

  print "<img src='/images/${DotColor}dot.jpg' alt='${DotColor} dot' " .
        "width='20' height='20' />";
}

sub GeneratePage
{
  my $self = shift;

  $self->{Request}->headers_out->add("Refresh", "60");

  $self->SUPER::GeneratePage(@_);
}

sub GenerateBody
{
  my $self = shift;

  print "<h1>${ProjectName} Test Bot status</h1>\n";
  print "<div class='Content'>\n";

  print "<h2>General</h2>\n";
  print "<div class='GeneralStatus'>\n";
  print "<div class='GeneralStatusItem'>";
  if (PingEngine())
  {
    $self->OutputDot("green");
    print "<div class='GeneralStatusItemText'><a href='#jobs'>Engine is alive and processing jobs</a></div>";
  }
  else
  {
    $self->OutputDot("red");
    print "<div class='GeneralStatusItemText'><a href='#jobs'>Engine appears to be dead and is not processing jobs</a></div>";
  }
  print "</div>\n";
  
  print "<div class='GeneralStatusItem'>";
  my $VMs = CreateVMs();
  $VMs->AddFilter("Status", ["offline"]);
  if ($VMs->IsEmpty())
  {
    $self->OutputDot("green");
    print "<div class='GeneralStatusItemText'><a href='#vms'>All VMs are online</a></div>";
  }
  else
  {
    $self->OutputDot("red");
    print "<div class='GeneralStatusItemText'><a href='#vms'>One or more VMs are offline</a></div>";
  }
  print "</div>\n";
  print "</div>\n";

  print "<h2><a name='jobs'></a>Jobs</h2>\n";
  my $JobsCollectionBlock = new JobStatusBlock(CreateJobs(), $self);
  $JobsCollectionBlock->GenerateList();

  print "<h2><a name='vms'></a>VMs</h2>\n";
  my $VMsCollectionBlock = new VMStatusBlock(CreateVMs(), $self);
  $VMsCollectionBlock->GenerateList();
  print "</div>\n";
}

package main;

my $Request = shift;

my $StatusPage = StatusPage->new($Request, "");
$StatusPage->GeneratePage();
