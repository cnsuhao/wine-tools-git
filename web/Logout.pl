# WineTestBot logout page
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

package LogoutPage;

use ObjectModel::CGI::Page;
use WineTestBot::CGI::Sessions;
use CGI qw(:standard);
use CGI::Cookie;

@LogoutPage::ISA = qw(ObjectModel::CGI::Page);

sub _initialize
{
  my $self = shift;

  $self->{WasLoggedIn} = undef;

  $self->GetPageBase()->CheckSecurePage();
}

sub GenerateBody
{
  my $self = shift;

  print "<h1>Log out</h1>";
  if ($self->{WasLoggedIn})
  {
    print "<p>You have been logged out</p>";
  }
  else
  {
    print "<p>It seems you're not logged in, so there is no need to log " .
          "out</p>";
  }
}

sub GeneratePage
{
  my $self = shift;

  my $Session = $self->GetCurrentSession();
  $self->{WasLoggedIn} = defined($Session);
  if ($self->{WasLoggedIn})
  {
    my $Sessions = CreateSessions();
    $Sessions->DeleteItem($Session);
    $self->SetCurrentSession(undef);
  }

  $self->SUPER::GeneratePage(@_);
}

package main;

my $Request = shift;

my $LogoutPage = LogoutPage->new($Request, "");
$LogoutPage->GeneratePage();
