# User details page
#
# Copyright 2009 Ge van Geldorp
# Copyright 2013 Francois Gouget
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

package UserDetailsPage;

use ObjectModel::CGI::ItemPage;
use WineTestBot::Config;
use WineTestBot::Users;

@UserDetailsPage::ISA = qw(ObjectModel::CGI::ItemPage);

sub _initialize
{
  my $self = shift;

  $self->SUPER::_initialize(@_, CreateUsers());
}

sub DisplayProperty
{
  my $self = shift;
  my $PropertyDescriptor = $_[0];

  my $PropertyName = $PropertyDescriptor->GetName();
  if (defined($LDAPServer) &&
      ($PropertyName eq "Password" || $PropertyName eq "ResetCode"))
  {
    return "";
  }

  return $self->SUPER::DisplayProperty(@_);
}

sub GetActions
{
  my $self = shift;

  my @Actions;
  if (!defined $LDAPServer and $self->{Item}->WaitingForApproval())
  {
    $Actions[0] = "Approve";
  }

  push(@Actions, @{$self->SUPER::GetActions()});

  return \@Actions;
}

sub OnApprove($)
{
  my $self = shift;

  return !1 if (!$self->Save());
  $self->{ErrMessage} = $self->{Item}->Approve();
  return !1 if (defined $self->{ErrMessage});
  $self->RedirectToList();
  exit;
}

sub OnAction
{
  my $self = shift;
  my $Action = $_[0];

  if ($Action eq "Approve")
  {
    return $self->OnApprove();
  }

  return $self->SUPER::OnAction(@_);
}

package main;

my $Request = shift;

my $UserDetailsPage = UserDetailsPage->new($Request, "admin");
$UserDetailsPage->GeneratePage();
