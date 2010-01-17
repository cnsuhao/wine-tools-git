# WineTestBot feedback page
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

package FeedbackPage;

use CGI qw(:standard escapeHTML);
use ObjectModel::BasicPropertyDescriptor;
use ObjectModel::CGI::FreeFormPage;
use WineTestBot::Config;

@FeedbackPage::ISA = qw(ObjectModel::CGI::FreeFormPage);

sub _initialize
{
  my $self = shift;

  my @PropertyDescriptors;
  $PropertyDescriptors[0] = CreateBasicPropertyDescriptor("Name", "Name", !1, !1, "A", 40);
  $PropertyDescriptors[1] = CreateBasicPropertyDescriptor("EMail", "EMail", !1, !1, "A", 40);
  $PropertyDescriptors[2] = CreateBasicPropertyDescriptor("Remarks", "Remarks", !1, 1, "A", 1024);

  $self->SUPER::_initialize(\@PropertyDescriptors);

  my $Session = $self->GetCurrentSession();
  if (defined($Session))
  {
    my $User = $Session->User;
    $self->{Name} = $User->RealName;
    $self->{EMail} = $User->EMail;
  }
  else
  {
    $self->{Name} = undef;
    $self->{EMail} = undef;
  }
}

sub GetPropertyValue
{
  my $self = shift;
  my $PropertyDescriptor = $_[0];

  if (defined($self->{$PropertyDescriptor->GetName()}))
  {
    return $self->{$PropertyDescriptor->GetName()};
  }

  return $self->SUPER::GetPropertyValue(@_);
}

sub GetTitle
{
  return "Provide feedback";
}

sub GetHeaderText
{
  return "Remarks on how to improve this service are highly appreciated! " .
         "If you wish to stay anonymously, you don't have to enter your name " .
         "or email address.";
}

sub GetInputType
{
  my $self = shift;
  my $PropertyDescriptor = $_[0];

  if (substr($PropertyDescriptor->GetName(), 0, 8) eq "Remarks")
  {
    return "textarea";
  }

  return $self->SUPER::GetInputType(@_);
}

sub GetActions
{
  my $self = shift;

  my $Actions = $self->SUPER::GetActions();
  push(@$Actions, "Send");

  return $Actions;
}
sub OnSend
{
  my $self = shift;

  if (! $self->Validate)
  {
    return !1;
  }

  open (SENDMAIL, "|/usr/sbin/sendmail -oi -t -odq");
  print SENDMAIL <<"EOF";
From: <$RobotEMail> (Marvin)
To: <$AdminEMail>
Subject: winetestbot feedback

EOF
  print SENDMAIL "Name: ", $self->GetParam("Name"), "\n";
  print SENDMAIL "EMail: ", $self->GetParam("EMail"), "\n\n";
  print SENDMAIL "Remarks:\n", $self->GetParam("Remarks"), "\n";
  close(SENDMAIL);

  return 1;
}

sub OnAction
{
  my $self = shift;
  my $Action = $_[0];

  if ($Action eq "Send")
  {
    return $self->OnSend();
  }

  return $self->SUPER::OnAction(@_);
}

sub GenerateBody
{
  my $self = shift;

  if ($self->{ActionPerformed})
  {
    print "<h1>Feedback sent</h1>\n";
    print "<p>Thanks for taking the time to provide feedback.</p>\n";
    return;
  }

  $self->SUPER::GenerateBody(@_);
}

package main;

my $Request = shift;

my $FeedbackPage = FeedbackPage->new($Request, "");
$FeedbackPage->GeneratePage();
