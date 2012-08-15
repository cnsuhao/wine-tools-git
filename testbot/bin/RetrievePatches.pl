#!/usr/bin/perl -Tw

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
  die "Usage: RetrievePatches.pl <StartPatchId> <EndPatchId>";
}

if ($StartPatchId =~ m/^(\d+)$/)
{
  $StartPatchId = $1;
}
else
{
  die "Invalid StartPatchId $StartPatchId";
}
if ($EndPatchId =~ m/^(\d+)$/)
{
  $EndPatchId = $1;
}
else
{
  die "Invalid EndPatchId $EndPatchId";
}
if ($EndPatchId < $StartPatchId)
{
  die "EndPatchId $EndPatchId shouldn't be smaller than StartPatchId $StartPatchId";
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
    LogMsg "RetrievePatches: Unexpected HTTP response code ", 
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
    LogMsg "RetrievePatches: can't create staging file $StagingFileName: $!\n";
    exit 1;
  }
  print STAGINGFILE $Response->decoded_content();
  close STAGINGFILE;

  PatchRetrieved("${FileNameRandomPart}_patch_$PatchId", $PatchId);

  LogMsg "RetrievePatches: retrieved patch $PatchId\n";
}

exit;
