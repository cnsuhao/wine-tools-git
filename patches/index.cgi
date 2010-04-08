#!/usr/bin/perl -w
#
# Patches CGI script
#
# Copyright 2009 Alexandre Julliard
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

use CGI qw(:standard);
use open ':utf8';
binmode STDOUT, ':utf8';

my %status_descr =
(
 "nil"        => "New",
 "pending"    => "Pending",
 "applied"    => "Applied",
 "committed"  => "Committed",
 "applyfail"  => "Apply failure",
 "buildfail"  => "Build failure",
 "formatting" => "Formatting",
 "other"      => "Other project",
 "nopatch"    => "No patch",
 "rejected"   => "Rejected",
 "split"      => "Needs splitting",
 "depend"     => "Dependency",
 "superseded" => "Superseded",
 "testcase"   => "Needs tests",
 "testfail"   => "Test failure",
);

my @legend =
(
 [ "nil",        "<ul><li>Patch not even looked at yet, there's still hope...</li></ul>" ],
 [ "pending",    "<ul><li>The patch is not obviously correct at first glance. Making a more convincing argument, preferably in the form of a test case, may help.</li>" .
                 "<li>Waiting for feedback from the main developer in that area.</li></ul>" ],
 [ "committed",  "<ul><li>You have done everything right; congratulations!</li>" .
                 "<li>You screwed up but AJ missed it, send a fix before someone notices ;-)</li></ul>" ],
 [ "depend",     "<ul><li>The patch is part of a series in which a previous patch hasn't been applied. Resend when the dependent patch is fixed.</li></ul>" ],
 [ "superseded", "<ul><li>An updated version of the patch has been submitted.</li>" .
                 "<li>Someone else fixed the problem already.</li></ul>" ],
 [ "testcase",   "<ul><li>You need to write some test cases demonstrating that the patch is correct.</li></ul>" ],
 [ "other",      "<ul><li>The patch belongs to another WineHQ project (website, appdb, etc.) and will be applied by the respective maintainer.</li></ul>" ],
 [ "applyfail",  "<ul><li>The patch got mangled in transit.</li>" .
                 "<li>It's not relative to the latest git.</li>" .
                 "<li>Someone else sent a patch that changes the same area and causes conflicts.</li>" .
                 "<li>The patch is relative to a subdirectory (using 'git format-patch' is strongly recommended).</li></ul>" ],
 [ "buildfail",  "<ul><li>Syntax error or other compile problem.</li>" .
                 "<li>You forgot to include some changes or new files required for compilation.</li>" .
                 "<li>The patch causes compiler warnings (maintainer mode implies -Werror).</li></ul>" ],
 [ "formatting", "<ul><li>The patch author's name or email address are incorrect or missing.</li>" .
                 "<li>Whitespace got mangled in transit.</li>" .
                 "<li>Indentation is messed up (usually from editing with a non-standard tab size).</li>" .
                 "<li>8-bit chars got mangled in transit (usually when sending patches to resource files).</li>" .
                 "<li>You are making gratuitous formatting changes to the code.</li>" .
                 "<li>You are using C++ comments.</li></ul>" ],
 [ "nopatch",    "<ul><li>You hit 'send' before attaching the patch.</li>" .
                 "<li>The mail is a reply to another patch, or spam.</li></ul>" ],
 [ "rejected",   "<ul><li>The patch has been rejected with a comment on wine-devel or #winehackers.</li>" .
                 "<li>The patch contains an obvious error that you are expected to figure out yourself.</li></ul>" ],
 [ "split",      "<ul><li>A single mail contained multiple patch files.</li>" .
                 "<li>The patch contains unrelated changes that should be sent as separate patches.</li>" .
                 "<li>The patch is simply too large for review, you need to find a way to split it.</li></ul>" ],
 [ "testfail",   "<ul><li>You didn't run 'make test' before submitting.</li>" .
                 "<li>The patch requires a Wine fix but doesn't use todo_wine.</li>" .
                 "<li>The patch fixes a failure but doesn't remove the corresponding todo_wine.</li></ul>" ],
);

my $dir = "data";
my %patches;

sub format_author($)
{
    my $_ = shift;
    if (/\s*((\"(.*)\")|(.*))\s*<(\S+\@\S+)>/) { return $3 || $4 || $5; }
    return $_;
}

print header( -charset => "utf-8" );
print start_html(-title=>"Patches list",
                 -encoding=>"utf-8",
                 -style=>{src=>"patches.css"});

print "<div class=\"main\">\n";
print "<table class=\"main\"><tr><th class=\"id\">ID</th>",
    "<th class=\"status\">Status</th>",
    "<th class=\"author\">Author</th>",
    "<th class=\"subject\">Subject</th></tr>\n";

opendir DIR, $dir;
foreach my $file (readdir DIR)
{
    next unless $file =~ /^[0-9]+$/;
    my %patch;
    next unless open PATCH, "<$dir/$file";
    while (<PATCH>)
    {
        if (/^Subject: (.*)$/) { $patch{"subject"} = $1; }
        elsif (/^From: (.*)$/) { $patch{"author"} = format_author($1); }
        last if (defined $patch{"subject"} && defined $patch{"author"});
    }
    close PATCH;

    $patch{"status"} = "nil";
    if (open STATUS, "<$dir/$file.status")
    {
        my $status = <STATUS>;
        chomp $status;
        $patch{"status"} = $status;
        close STATUS;
    }
    $patch{"order"} = $file;
    if (open ORDER, "<$dir/$file.order")
    {
        $patch{"order"} = <ORDER>;
        close ORDER;
    }
    $patches{$file} = \%patch;
}
closedir DIR;

my $row = 0;
foreach my $file (sort { $patches{$b}->{"order"} <=> $patches{$a}->{"order"} } keys %patches)
{
    my $patch = $patches{$file};
    printf "<tr class=\"%s %s\"><td class=\"id\">%s</td><td class=\"status\"><a href=\"#legend\">%s</a></td><td class=\"author\">%s</td>",
           $row & 1 ? "odd" : "even", $patch->{"status"}, $file, $status_descr{$patch->{"status"}} || $patch->{"status"},
           escapeHTML($patch->{"author"});
    printf "<td class=\"subject\"><a href=\"data/$file\">%s</a></td></tr>\n",
           escapeHTML($patch->{"subject"});
    $row++;
}
print "</table></div>\n";

$row = 0;
print "<div class=\"legend\"><h2><a name=\"legend\">Legend</a></h2>\n";
print "<table class=\"legend\"><tr><th class=\"status\">Status</th><th class=\"causes\">Possible causes</th></tr>\n";
foreach my $status (@legend)
{
    printf "<tr class=\"%s\"><td class=\"status %s\">%s</td><td class=\"causes\">%s</td></tr>\n",
           $row & 1 ? "odd" : "even", $status->[0], $status_descr{$status->[0]}, $status->[1];
    $row++;
    
}
print "</table></div>\n";
print end_html;
