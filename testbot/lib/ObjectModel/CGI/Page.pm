# Base class for web pages
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

ObjectModel::CGI::Page - Base class for web pages

=cut

package ObjectModel::CGI::Page;

use CGI;

use vars qw(@ISA @EXPORT $PageBaseCreator);

require Exporter;
@ISA = qw(Exporter);
@EXPORT = qw(new SetPageBaseCreator);

sub new
{
  my $class = shift;
  my ($Request, $RequiredRole) = @_;

  my $self = {Request => $Request,
              CGIObj => CGI->new($Request),
              ErrMessage => undef,
              ErrField => undef};
  $self = bless $self, $class;
  $self->{PageBase} = &$PageBaseCreator($self, @_);
  $self->_initialize($Request, $RequiredRole);
  return $self;
}

sub _initialize
{
  #my ($self, $Request, $RequiredRole) = @_;
}

sub GetParam
{
  my $self = shift;

  return $self->{CGIObj}->param(@_);
}

sub CGI
{
  my $self = shift;

  return $self->{CGIObj};
}

sub escapeHTML
{
  my $self = shift;

  return $self->{CGIObj}->escapeHTML(@_);
}

sub GetPageBase
{
  my $self = shift;

  return $self->{PageBase};
}

sub GenerateHttpHeaders
{
  my $self = shift;

  $self->{PageBase}->GenerateHttpHeaders($self);
}

sub UnsetCookies
{
  my $self = shift;

  $self->{PageBase}->UnsetCookies($self);
}

sub SetCookies
{
  my $self = shift;

  $self->{PageBase}->SetCookies($self);
}

sub GetPageTitle
{
  my $self = shift;

  return $self->{PageBase}->GetPageTitle($self);
}

sub GetTitle
{
  my $self = shift;

  return undef;
}

sub GenerateHeader
{
  my $self = shift;

  $self->{PageBase}->GenerateHeader($self);
}

sub GenerateFooter
{
  my $self = shift;

  $self->{PageBase}->GenerateFooter($self);
}

sub GenerateErrorDiv
{
  my $self = shift;

  $self->{PageBase}->GenerateErrorDiv($self);
}

sub GenerateErrorPopup
{
  my $self = shift;

  $self->{PageBase}->GenerateErrorPopup($self);
}

sub GenerateBody
{
  my $self = shift;

  die "Pure virtual function " . ref($self) . "::GenerateBody called";
}

sub GeneratePage
{
  my $self = shift;

  $self->GenerateHttpHeaders();
  $self->GenerateHeader();
  $self->GenerateBody();
  $self->GenerateFooter();
}

sub Redirect
{
  my $self = shift;

  $self->{PageBase}->Redirect($self, @_);
}

sub GetCurrentSession
{
  my $self = shift;

  return $self->{PageBase}->GetCurrentSession();
}

sub SetCurrentSession
{
  my $self = shift;

  $self->{PageBase}->SetCurrentSession($self, @_);
}

sub GetErrMessage
{
  my $self = shift;

  return $self->{ErrMessage};
}

sub GetErrField
{
  my $self = shift;

  return $self->{ErrField};
}

sub SetPageBaseCreator
{
  $PageBaseCreator = shift;
}

1;
