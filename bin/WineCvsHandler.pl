#!/usr/bin/perl -Tw
#
# Tell the engine to expect a winetest.exe update on test.winehq.org

use strict;

use lib("/usr/lib/winetestbot/lib");
use WineTestBot::Engine::Notify;

ExpectWinetestUpdate();

exit 0;
