use strict;

use lib qw(/usr/lib/winetestbot/lib);

use ObjectModel::CGI::Page;
use WineTestBot::CGI::PageBase;

SetPageBaseCreator(\&CreatePageBase);

1;
