# Register account page
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

package RegisterPage;

use URI::Escape;
use ObjectModel::CGI::ItemPage;
use WineTestBot::Config;
use WineTestBot::Users;
use WineTestBot::Utils;

@RegisterPage::ISA = qw(ObjectModel::CGI::ItemPage);

sub _initialize
{
  my $self = shift;

  $self->SUPER::_initialize(@_, CreateUsers());
}

sub GetTitle
{
  return "Request new account";
}

sub GetHeaderText
{
  return "Since an account will allow you to run code on this system, your " .
         "request for an account will have to be manually approved. That " .
         "should be no problem if you're a well-known member of the Wine " .
         "community.<br>\n" .
         "When your request has been approved, you'll receive a link via " .
         "email to activate your account and choose a password. Usually, " .
         "you should receive that email within a couple of hours.";
}

sub GetFooterText
{
  return "Your real name and email address will be treated confidentially " .
         "and will not be shown on any bot-accessible part of this site.";
}

sub DisplayProperty
{
  my $self = shift;
  my $PropertyDescriptor = $_[0];

  my $PropertyName = $PropertyDescriptor->GetName();

  my $Display;
  if ($PropertyName ne "Name" && $PropertyName ne "EMail" &&
      $PropertyName ne "RealName")
  {
    return "";
  }

  return $self->SUPER::DisplayProperty(@_);
}

sub GenerateFields
{
  my $self = shift;

  print "<div><input type='hidden' name='Active' value='Y'></div>\n";
  $self->SUPER::GenerateFields();
  print "<div class='DetailProperty'><label>Remarks</label><textarea name='Remarks' cols='40' rows='4'></textarea></div>\n";
  $self->GenerateRequiredLegend();
  $self->{HasRequired} = !1;
}

sub GenerateActions
{
  print <<EOF;
<div class='DetailActions'>
<input type='submit' name='Action' value='Send request' />
</div>
EOF
}

sub OnSendRequest
{
  my $self = shift;

  if (! $self->Save())
  {
    return !1;
  }

  my $Msg = "Username: " . $self->GetParam("Name") . "\n" .
            "EMail: " . $self->GetParam("EMail") . "\n" .
            "Real name: " . $self->GetParam("RealName") . "\n";
  if ($self->GetParam("Remarks"))
  {
    $Msg .= "Remarks:\n" . $self->GetParam("Remarks") . "\n";
  }
  my $URL = MakeSecureURL("/admin/UserDetails.pl?Key=" .
                          uri_escape($self->GetParam("Name")));
  $Msg .= "\nTo approve or deny the request, please go to " . $URL;

  open (SENDMAIL, "|/usr/sbin/sendmail -oi -t -odq");
  print SENDMAIL <<"EOF";
From: <$AdminEMail> (Marvin)
To: <$AdminEMail>
Subject: winetestbot account request

$Msg
EOF
  close(SENDMAIL);

  return 1;
}

sub OnAction
{
  my $self = shift;
  my $Action = $_[0];

  if ($Action eq 'Send request')
  {
    return $self->OnSendRequest(@_);
  }

  return $self->SUPER::OnAction(@_);
}

sub GenerateBody
{
  my $self = shift;

  if ($self->{ActionPerformed})
  {
    print <<EOF;
<h1>Request new account</h1>
<p>Your request is now waiting to be approved. Expect to receive a link via
email to activate your account and choose a password. Usually, you should
receive that email within a couple of hours.</p>
EOF
    return;
  }

  $self->SUPER::GenerateBody(@_);
}

package main;

my $Request = shift;

my $RegisterPage = RegisterPage->new($Request, "");
$RegisterPage->GeneratePage();
