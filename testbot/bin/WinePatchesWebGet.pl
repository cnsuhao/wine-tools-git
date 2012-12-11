#!/usr/bin/perl -Tw
#
# Retrieve the latest patches from http://source.winehq.org/patches and submit
# them for testing. See also WinePatchesWebNotify.pl.
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

sub BEGIN
{
  if ($0 !~ m=^/=)
  {
    # Turn $0 into an absolute path so it can safely be used in @INC
    require Cwd;
    $0 = Cwd::cwd() . "/$0";
  }
  if ($0 =~ m=^(/.*)/[^/]+/[^/]+$=)
  {
    $::RootDir = $1;
    unshift @INC, "$::RootDir/lib";
  }
}

use LWP::UserAgent;
use HTTP::Request;
use HTTP::Response;
use HTTP::Status;
use WineTestBot::Config;
use WineTestBot::Log;
use WineTestBot::Utils;
use WineTestBot::Engine::Notify;

my ($StartWebPatchId, $EndWebPatchId) = @ARGV;
if (! $StartWebPatchId || ! $EndWebPatchId)
{
  die "Usage: WinePatchesWebGet.pl <StartWebPatchId> <EndWebPatchId>";
}

if ($StartWebPatchId =~ m/^(\d+)$/)
{
  $StartWebPatchId = $1;
}
else
{
  die "WinePatchesWebGet: Invalid StartWebPatchId $StartWebPatchId";
}
if ($EndWebPatchId =~ m/^(\d+)$/)
{
  $EndWebPatchId = $1;
}
else
{
  die "WinePatchesWebGet: Invalid EndWebPatchId $EndWebPatchId";
}
if ($EndWebPatchId < $StartWebPatchId)
{
  die "WinePatchesWebGet: EndWebPatchId $EndWebPatchId shouldn't be smaller than StartWebPatchId $StartWebPatchId";
}

my $BaseURL = "http://source.winehq.org/patches/data";

my $UA = LWP::UserAgent->new();
$UA->agent("WineTestBot");

foreach my $WebPatchId ($StartWebPatchId..$EndWebPatchId)
{
  my $Request = HTTP::Request->new(GET => "$BaseURL/$WebPatchId");
  my $Response = $UA->request($Request);
  if ($Response->code != RC_OK)
  {
    LogMsg "Unexpected HTTP response code ", $Response->code, "\n";
    exit 1;
  }
  my $FileNameRandomPart = GenerateRandomString(32);
  while (-e "$DataDir/staging/${FileNameRandomPart}_patch_$WebPatchId")
  {
    $FileNameRandomPart = GenerateRandomString(32);
  }
  my $StagingFileName = "$DataDir/staging/${FileNameRandomPart}_patch_$WebPatchId";
  if (! open STAGINGFILE, ">$StagingFileName")
  {
    LogMsg "Can't create staging file $StagingFileName: $!\n";
    exit 1;
  }
  print STAGINGFILE $Response->decoded_content();
  close STAGINGFILE;

  WinePatchWebSubmission("${FileNameRandomPart}_patch_$WebPatchId", $WebPatchId);

  LogMsg "Retrieved patch $WebPatchId\n";
}

exit;
