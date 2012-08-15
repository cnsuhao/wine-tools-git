#!/usr/bin/perl -Tw
#
# Tell the engine to expect a winetest.exe update on test.winehq.org

use strict;

my $Dir;
sub BEGIN
{
  $0 =~ m=^(.*)/[^/]*$=;
  $Dir = $1;
}
use lib "$Dir/../lib";

use File::Copy;
use WineTestBot::Config;
use WineTestBot::Utils;
use WineTestBot::Engine::Notify;

# Store the message in the staging dir
my $FileNameRandomPart = GenerateRandomString(32);
while (-e ("$DataDir/staging/${FileNameRandomPart}_patchnotification"))
{
  $FileNameRandomPart = GenerateRandomString(32);
}
copy(\*STDIN, "$DataDir/staging/${FileNameRandomPart}_patchnotification");

# Let the engine handle it
PatchNotification("${FileNameRandomPart}_patchnotification");

exit 0;
