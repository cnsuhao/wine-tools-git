#!/usr/bin/perl
#
# This script replays errors to the wine-tests-results mailing list
#
# Copyright (C) 2004 Brian Vincent
# Copyright (C) 2004 Dimitrie O. Paun
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
# Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
#
use CGI qw(:standard);
$CGI::POST_MAX = 50 * 1024;

print "Content-type: text/plain\n\n";

# first check for errors
my $error = cgi_error ();
if ($error) {
    print $error;
} else {
    open(MAIL,"|/usr/lib/sendmail -t");
    print MAIL "To: wine-tests-results\@winehq.org\n";
    print MAIL "From: winetest\@winehq.org\n";
    print MAIL "Reply-To: wine-devel\@winehq.org\n";
    print MAIL "Subject: [ERROR] winetest error report\n";
    print MAIL "\n";
    my $fh = upload('reportfile');
    while (<$fh>) {
	print MAIL "$_";
    }
    close(MAIL);

    print "OK\n";
}
