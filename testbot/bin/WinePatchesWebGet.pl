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

my $Dir;
sub BEGIN
{
  $0 =~ m=^(.*)/[^/]*$=;
  $Dir = $1;
}
use lib "$Dir/../lib";

use LWP::UserAgent;
use HTTP::Request;
use HTTP::Response;
use HTTP::Status;
use WineTestBot::Config;
use WineTestBot::Log;
use WineTestBot::Utils;
use WineTestBot::Engine::Notify;

my ($StartPatchId, $EndPatchId) = @ARGV;
if (! $StartPatchId || ! $EndPatchId)
{
  die "Usage: WinePatchesWebGet.pl <StartPatchId> <EndPatchId>";
}

if ($StartPatchId =~ m/^(\d+)$/)
{
  $StartPatchId = $1;
}
else
{
  die "WinePatchesWebGet: Invalid StartPatchId $StartPatchId";
}
if ($EndPatchId =~ m/^(\d+)$/)
{
  $EndPatchId = $1;
}
else
{
  die "WinePatchesWebGet: Invalid EndPatchId $EndPatchId";
}
if ($EndPatchId < $StartPatchId)
{
  die "WinePatchesWebGet: EndPatchId $EndPatchId shouldn't be smaller than StartPatchId $StartPatchId";
}

my $BaseURL = "http://source.winehq.org/patches/data";

my $UA = LWP::UserAgent->new();
$UA->agent("WineTestBot");

foreach my $PatchId ($StartPatchId..$EndPatchId)
{
  my $Request = HTTP::Request->new(GET => "$BaseURL/$PatchId");
  my $Response = $UA->request($Request);
  if ($Response->code != RC_OK)
  {
    LogMsg "WinePatchesWebGet: Unexpected HTTP response code ",
           $Response->code, "\n";
    exit 1;
  }
  my $FileNameRandomPart = GenerateRandomString(32);
  while (-e "$DataDir/staging/${FileNameRandomPart}_patch_$PatchId")
  {
    $FileNameRandomPart = GenerateRandomString(32);
  }
  my $StagingFileName = "$DataDir/staging/${FileNameRandomPart}_patch_$PatchId";
  if (! open STAGINGFILE, ">$StagingFileName")
  {
    LogMsg "WinePatchesWebGet: can't create staging file $StagingFileName: $!\n";
    exit 1;
  }
  print STAGINGFILE $Response->decoded_content();
  close STAGINGFILE;

  WinePatchWebSubmission("${FileNameRandomPart}_patch_$PatchId", $PatchId);

  LogMsg "WinePatchesWebGet: retrieved patch $PatchId\n";
}

exit;
