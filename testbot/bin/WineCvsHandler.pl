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

use WineTestBot::Engine::Notify;

ExpectWinetestUpdate();

exit 0;
