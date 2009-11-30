# WineTestBot password reset page
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

require "Config.pl";

package ResetPasswordPage;

use CGI qw(:standard escapeHTML);
use ObjectModel::BasicPropertyDescriptor;
use ObjectModel::CGI::FreeFormPage;
use WineTestBot::Users;
use WineTestBot::Utils;
use WineTestBot::CGI::Sessions;

@ResetPasswordPage::ISA = qw(ObjectModel::CGI::FreeFormPage);

sub _initialize
{
  my $self = shift;

  $self->GetPageBase()->CheckSecurePage();

  my @PropertyDescriptors;
  $PropertyDescriptors[0] = CreateBasicPropertyDescriptor("Name", "Username", 1, 1, "A", 40);
  $PropertyDescriptors[1] = CreateBasicPropertyDescriptor("ResetCode", "Activation code", !1, 1, "A", 32);
  $PropertyDescriptors[2] = CreateBasicPropertyDescriptor("Password1", "Password", !1, 1, "A", 32);
  $PropertyDescriptors[3] = CreateBasicPropertyDescriptor("Password2", "Password (repeat)", !1, 1, "A", 32);

  $self->SUPER::_initialize(\@PropertyDescriptors);
}

sub GetTitle
{
  return "Reset passwor";
}

sub GetHeaderText
{
  return "If you don't have an account yet, you can " .
         "<a href='Register.php'>register</a> for one.";
}

sub GetInputType
{
  my $self = shift;
  my $PropertyDescriptor = $_[0];

  if (substr($PropertyDescriptor->GetName(), 0, 8) eq "Password")
  {
    return "password";
  }

  return $self->SUPER::GetInputType(@_);
}

sub GetActions
{
  my $self = shift;

  my $Actions = $self->SUPER::GetActions();
  push(@$Actions, "Change password");

  return $Actions;
}

sub Validate
{
  my $self = shift;

  if (! $self->SUPER::Validate())
  {
    return !1;
  }

  if ($self->GetParam("Password1") ne $self->GetParam("Password2"))
  {
    $self->{ErrField} = "Password1";
    $self->{ErrMessage} = "Passwords don't match";
    return !1;
  }

  return 1;
}

sub OnChangePassword
{
  my $self = shift;

  if (! $self->Validate)
  {
    return !1;
  }

  my $OldSession = $self->GetCurrentSession();

  my $Users = CreateUsers();
  my $User = $Users->GetItem($self->GetParam("Name"));
  if (! defined($User))
  {
    $self->{ErrField} = "Name";
    $self->{ErrMessage} = "Unknown username or incorrect activation code";
    return !1;
  }
  $self->{ErrMessage} = $User->ResetPassword($self->GetParam("ResetCode"),
                                             $self->GetParam("Password1"));
  if (defined($self->{ErrMessage}))
  {
    $self->{ErrField} = "Name";
    return !1;
  }

  my ($ErrMessage, $User) = $Users->Authenticate($self->GetParam("Name"),
                                                 $self->GetParam("Password1"));
  if ($ErrMessage)
  {
    $self->{ErrMessage} = $ErrMessage;
    $self->{ErrField} = "Name";
    return !1;
  }

  my $Sessions = CreateSessions();
  ($ErrMessage, my $Session) = $Sessions->NewSession($User,
                                                     defined($self->GetParam("AutoLogin")));
  if ($ErrMessage)
  {
    $self->{ErrMessage} = $ErrMessage;
    $self->{ErrField} = "Name";
    return !1;
  }

  if ($OldSession)
  {
    $Sessions->DeleteItem($OldSession);
  }

  $self->SetCurrentSession($Session);

  return 1;
}

sub OnAction
{
  my $self = shift;
  my $Action = $_[0];

  if ($Action eq "Change password")
  {
    return $self->OnChangePassword();
  }

  return $self->SUPER::OnAction(@_);
}

sub GenerateBody
{
  my $self = shift;

  if ($self->{ActionPerformed})
  {
    print "<h1>Reset password</h1>\n";
    print "<p>Your password was successfully changed.</p>\n";
    return;
  }

  $self->SUPER::GenerateBody(@_);
}

package main;

my $Request = shift;

my $ResetPasswordPage = ResetPasswordPage->new($Request, "");
$ResetPasswordPage->GeneratePage();
