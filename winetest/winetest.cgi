#!/usr/bin/perl
#
# Copyright (C) 2004 Ferenc Wagner
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

use strict;
use warnings;
use vars qw/$maxfilesize/;

BEGIN {
    require "winetest.conf";
}

use File::Copy;
use File::Temp qw(tempdir);
use CGI qw(:standard);
# Cater for some overhead
$CGI::POST_MAX = $maxfilesize + 1024;
$ENV{TMPDIR} = "$::workdir/queue";

my $name = param ("reportfile");
my $error = cgi_error ();

sub test_reportfile()
{
    my $buffer;
    my $fh = upload "reportfile";
    read $fh, $buffer, 1024;
    $buffer =~ /^Version \d+\r?\nTests from build ([-.0-9a-zA-Z]+)\r?\n/s;
    return $1;
}

sub move_file($)
{
    my ($filename) = @_;
    my $orig = tmpFileName($filename);
    my $tmpdir = tempdir ("repXXXXX", DIR => "$::workdir/queue");
    chmod 0777, $tmpdir;
    chmod 0666&~umask, $orig;
    my $size = -s $orig;
    # Note that we are stealing CGI's temporary file which typically results
    # in a warning in the web server's logs. Still seems to work though.
    (move $orig, "$tmpdir/report")?
      "Received $filename ($size bytes).\n":
      "Error: can't store $filename: $!\n";
}

# Invoked by winetest

if (user_agent ("Winetest Shell")) {
    print header ("text/plain");
    if ($error) {
        print "Error: $error\n";
    } elsif ($name) {
        my $build = test_reportfile();
        if (!defined $build) {
            print "Error: submission corrupted";
        } elsif ($build eq "-") {
            print "Error: build ID unset";
        } else {
            print move_file($name);
        }
    } else {
        print "Error: empty request\n";
    }
    exit;
}

# Invoked by a browser

print header,
  start_html ("Winetest report upload"),
  h1 ("Winetest report upload"),
  start_multipart_form (),
  "The name of the report file:",
  filefield ("reportfile","c:\\temp\\res",45),
  p,
  reset, submit ("submit","Upload File"),
  end_form(),
  hr;

if ($error) {
    print h2 ("Error during file upload ($name)"),
      strong ($error);
} elsif ($name) {
    my $build = test_reportfile();
    if (!defined $build) {
        print h2 ("Error: submission corrupted");
    } elsif ($build eq "-") {
        print h2 ("Error: build ID unset");
    } else {
        print h2 (move_file($name));
    }
}
print end_html;
