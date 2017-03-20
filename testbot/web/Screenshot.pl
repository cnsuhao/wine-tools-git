# Sends a Task's current screenshot
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

use Apache2::Const -compile => qw(REDIRECT);
use CGI;
use CGI::Cookie;
use Fcntl;
use WineTestBot::Config;
use WineTestBot::CGI::Sessions;
use WineTestBot::Engine::Notify;
use WineTestBot::VMs;

sub NotAvailable($)
{
  my ($Request) = @_;

  $Request->headers_out->set("Location", "/images/NotAvailable.png");
  $Request->status(Apache2::Const::REDIRECT);
  exit;
}

sub LiveScreenshot($$)
{
  my ($Request, $VMName) = @_;

  my $VMs = CreateVMs();
  my $VM = $VMs->GetItem($VMName);
  if (! defined($VM))
  {
    return undef;
  }
  
  my $Available = !0;
  if ($VM->Status eq "running")
  {
    $Available = 1;
  }
  else
  {
    my %Cookies = CGI::Cookie->fetch($Request);
    if (defined($Cookies{"SessionId"}))
    {
      my $Session = CreateSessions()->GetItem($Cookies{"SessionId"}->value);
      $Available = $Session->User->HasRole("admin");
    }
  }
  
  if (! $Available)
  {
    return undef;
  }
  
  my ($ErrMessage, $ImageBytes) = GetScreenshot($VMName);
  if (defined($ErrMessage))
  {
    return undef;
  }
  
  return $ImageBytes;
}

sub StoredScreenshot($$$$)
{
  my ($Request, $JobKey, $StepKey, $TaskKey) = @_;

  # Validate and untaint
  if (! ($JobKey =~ m/^(\d+)$/))
  {
    return undef;
  }
  $JobKey = $1;
  if (! ($StepKey =~ m/^(\d+)$/))
  {
    return undef;
  }
  $StepKey = $1;
  if (! ($TaskKey =~ m/^(\d+)$/))
  {
    return undef;
  }
  $TaskKey = $1;

  my $FileName = "$DataDir/jobs/$JobKey/$StepKey/$TaskKey/screenshot.png";
  if (! sysopen(SCREENSHOT, $FileName, O_RDONLY))
  {
    return undef;
  }
  my $BlkSize = (stat SCREENSHOT)[11] || 16384;
  my $ImageBytes;
  my $ImageSize = 0;
  my $Len;
  while ($Len = sysread(SCREENSHOT, $ImageBytes, $BlkSize, $ImageSize))
  {
    if (! defined($Len))
    {
      close SCREENSHOT;
      return undef;
    }
    $ImageSize += $Len;
  }
  close SCREENSHOT;
 
  return $ImageBytes;
}

my $Request = shift;

my $CGIObj = CGI->new($Request);
my $VMName = $CGIObj->param("VMName");
my $JobKey = $CGIObj->param("JobKey");
my $StepKey = $CGIObj->param("StepKey");
my $TaskKey = $CGIObj->param("TaskKey");
my $ImageBytes;
if (defined($VMName))
{
  $ImageBytes = LiveScreenshot($Request, $VMName)
}
elsif (defined($JobKey) && defined($StepKey) && defined($TaskKey))
{
  $ImageBytes = StoredScreenshot($Request, $JobKey, $StepKey, $TaskKey)
}
  
if (defined($ImageBytes))
{
  # Date in the past
  $Request->headers_out->add("Expires", "Sun, 25 Jul 1997 05:00:00 GMT");
  
  # always modified
  $Request->headers_out->add("Last-Modified", (scalar gmtime) . " GMT");
  
  # HTTP/1.1
  $Request->headers_out->add("Cache-Control", "no-cache, must-revalidate, " .
                                              "post-check=0, pre-check=0");
  
  # HTTP/1.0
  $Request->headers_out->add("Pragma", "no-cache");
  
  # PNG file
  $Request->content_type("image/png");

  print $ImageBytes;
}
else
{
  NotAvailable($Request);
}

exit;
