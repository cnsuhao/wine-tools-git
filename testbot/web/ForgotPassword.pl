# WineTestBot password reminder page
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

package ForgotPasswordPage;

use CGI qw(:standard escapeHTML);
use ObjectModel::BasicPropertyDescriptor;
use ObjectModel::CGI::FreeFormPage;
use WineTestBot::Users;
use WineTestBot::Utils;
use WineTestBot::CGI::Sessions;

@ForgotPasswordPage::ISA = qw(ObjectModel::CGI::FreeFormPage);

sub _initialize
{
  my $self = shift;

  $self->GetPageBase()->CheckSecurePage();

  my @PropertyDescriptors = (
    CreateBasicPropertyDescriptor("Name", "Username or EMail", 1, 1, "A", 40),
  );

  $self->SUPER::_initialize(\@PropertyDescriptors);
}

sub GetTitle
{
  return "Reset password";
}

sub GetHeaderText
{
  return "Please enter your username or your email address<br>\n" .
         "If you don't have an account yet, you can " .
         "<a href='Register.pl'>register</a> for one.";
}

sub GetActions
{
  my $self = shift;

  my $Actions = $self->SUPER::GetActions();
  push(@$Actions, "Reset password");

  return $Actions;
}

sub OnResetPassword
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
    $Users = CreateUsers();
    $Users->AddFilter("EMail", [$self->GetParam("Name")]);
    my $Keys = $Users->GetKeys;
    if (scalar @$Keys == 0)
    {
      $self->{ErrField} = "Name";
      $self->{ErrMessage} = "Unknown username or email address";
      return !1;
    }
    $User = $Users->GetItem($Keys->[0]);
  }

  $self->{ErrMessage} = $User->SendResetCode();
  if (defined($self->{ErrMessage}))
  {
    $self->{ErrField} = "Name";
    return !1;
  }

  return 1;
}

sub OnAction
{
  my $self = shift;
  my $Action = $_[0];

  if ($Action eq "Reset password")
  {
    return $self->OnResetPassword();
  }

  return $self->SUPER::OnAction(@_);
}

sub GenerateBody
{
  my $self = shift;

  if ($self->{ActionPerformed})
  {
    print "<h1>Reset password</h1>\n";
    print "<div class='Content'>\n";
    print "<p>A password activation code has been mailed to you.</p>\n";
    print "</div>\n";
    return;
  }

  $self->SUPER::GenerateBody(@_);
}

package main;

my $Request = shift;

my $ForgotPasswordPage = ForgotPasswordPage->new($Request, "");
$ForgotPasswordPage->GeneratePage();
