#!/usr/bin/perl
# 
# This script acts as the middle man between people who build
# tests to be distributed to Windows clients and the actual
# Windows clients
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
# We expect our input to be one of two things:
# - publish a new file for clients to download
#     ?publish=http://myserver.com/path/to/current-winetest.exe
# - a request to download that looks like:
#     ?winrash=1&cookie_name1=cookie_value1&cookie_name2=cookie_value2...
#
# We rely on the server to have directories available for every
# program that can be published.  For example, we need a winetest directory:
#   winetest/
#            <name>.url	contains url to find latest winetests at, must be
#			writable
#            url.mask	contains a reg ex to match against, only needs to 
#                       be read-only, in the above example it might be 
#			something like: http://myserver/com/path/to
#            <name>.cookie contains a unique identifier of a program that
#			winrash clients can download, must be writable

use Digest::MD5;
use CGI qw(:standard);
$CGI::POST_MAX = 50 * 1024;

$data_root="/home/winehq/opt/winetest";
$lynx="/usr/bin/lynx";
@valid_programs=("winrash", "winetest");

&main;

sub main {
    my ($build, $urls, $cookies);

    print "Content-type: text/plain\n\n";

    # first check for errors
    my $error = cgi_error ();
    if ($error) {
	print $error;
        exit;
    }

    my $publish = param('publish');
    if ($publish) {
        my $response = &releases_make($publish);
        print "$response\n";
        exit;
    }

    # for each of the programs we know about, see if they need an update
    foreach $program (@valid_programs) {
        ($build, $urls, $cookies) = &releases_read($program);
        if (param($program)) {
	    my @history = split(/,/, param("$program" . "_history"));
	    push (@history, param($program));
	    my @newhist = ();
	    foreach (@history) {
		my ($prg, $rel) = split(/-/, $_);
		if (($prg eq $program) and ($rel eq $build)) {
	            delete $$urls{$_};
	            delete $$cookies{$_};
		    push (@newhist, $_);
		}
	    }
	    $winetest_history = join ',', @newhist;
        }
	if (scalar(%$urls)) {
            &send_upgrade($urls, $winetest_history);
	    $update_sent = 1;
	    last;
	}
    }
    if (!$update_sent) {
        print "sleep 3600\n";
        return;
    }

}

##########################################################################
#
# When we publish, we:
# 1) Look for <publish key value>/url.mask that had to have been 
#    created by a web server admin thus ensuring this program is
#    approved for testing
# 2) Download the cookie for the program from that web server
# 3) Save that cookie to <publish key value>/<name>.cookie
# 4) Save the url to <publish key value>/<name>.url
#
##########################################################################

# removes the current release from disk
sub releases_purge {
    my ($project) = @_;
    system("rm -f $data_root/*/$project/*.cookie");
    system("rm -f $data_root/*/$project/*.url");
}

# this function reads the current release information from disk
# and returns ($thisrelease, %url, %cookies)
# where the two maps are keyed by the full file name of the release
sub releases_read {
    my ($project) = @_;
    my (%urls, %cookies, $thisrelease);

    @files = split(/\n/, `ls $data_root/*/$project/*.url`);
    foreach $file (@files) {
	if (open(GENERIC_FH, $file)) {
	    my ($cookiefile, $key, $url, $this_line);
	    $this_line = <GENERIC_FH>;
	    close(GENERIC_FH);
	    chomp $this_line;
	    $file =~ /(.*)\/(.*)\.url/;
	    $cookiefile = "$1/$2.cookie";
	    $key = $2;
	    $url = $this_line;
	    if (open(GENERIC_FH, $cookiefile)) {
	        my ($program, $release, @other);
		$this_line = <GENERIC_FH>;
		close(GENERIC_FH);
		chomp $this_line;
		($program, $release, @other) = split(/-/, $key);
		if (scalar(%urls) == 0) {
		    $thisrelease = $release;
		} elsif ($thisrelease ne $release) {
		    &debug("Invalid release state!") && die;
		}
	        $urls{$key} = $url;
		$cookies{$key} = $this_line;
	    }
	}
    }
    return ($thisrelease, \%urls, \%cookies);
}

# try to add a new release to our portfolio
sub releases_make {
    my ($url) = @_;
    my ($name, $program, $build, $publisher);
    my ($urls, $cookies, $current_build, @other);
    my ($build_path, $cookie, $program_ok);

    # parse out this release's information
    $url =~ /.*\/(.*)/;
    $name = $1;
    ($program, $build, $publisher, @other) = split(/-/, $name);

    # check that it's a recognized program
    foreach $prg (@valid_programs) {
	if ($prg eq $program) {
	    $program_ok = 1;
	    last;
	}
    }
    if (!$program_ok) {
	return "Invalid program";
    }

    # FIXME: maybe we should check here that $build is sane

    # test if this is a valid publisher
    if (opendir(IMD, "$data_root/$publisher/")) {
	closedir(IMD);
    } else {
	return "Invalid publisher";
    }

    # get current release info
    ($current_build, $urls, $cookies) = &releases_read($program);

    # check to see how we should handle it
    if ($build lt $current_build) {
	return "Build is old, current build is $current_build";
    }
    if ($build ne $current_build) {
	&releases_purge($program);
    }

    # check to see that the URL has the right format
    $base_path = "$data_root/$publisher/$program";

    $url_mask = &read_one_line("<$base_path/url.mask");
    if (!($url =~ $url_mask)) {
	return "Unrecognized URL format";
    }

    # get the cookie now
    $cookie = &read_one_line("$lynx -source $url.sig |");

    # all is good, store the cookie, and URL now, this activetes the release
    &write_file(">$base_path/$name.cookie", &md5sum($cookie));
    &write_file(">$base_path/$name.url", $url);

    return "OK";
}


##########################################################################
# 
# Issue commands understood by winrash.  Try to be somewhat intelligent
# in figuring out what needs to be sent.  
#
##########################################################################

sub send_upgrade {
    my ($urls, $history) = @_;
    my (@names, $name, $url, $program);
    my ($build, $publisher, $id, @other);

    # pick a release to send, the first will do
    @names = keys %$urls;
    $name = $names[0];

    # parse out this release's information
    $url = $$urls{$name};
    ($program, $build, $publisher, @other) = split(/-/, $name);

    &debug("Send upgrade received: $url");

    print "error_url http://test.winehq.org/error\n";
    print "error_sleep 3600\n";

    print "download $name $url\n";

    if ($program eq "winrash") {
	print "run $name /S\n";
        return;
    }

    # Set cookie now in case any commands following bomb.
    print "cookie $program $name\n";
    print "cookie $program" . "_history $history\n";

    if (substr($name, -4, 4) =~ ".zip") {
	print "unzip $name\n";
	$name =~ s/zip/exe/g;
    }
    $id = param('id');
    print "run $name -c -t $id\n";

    # wait just 5min, we may have other stuff to execute right away
    print "sleep 300\n";
}

##########################################################################
#
# Some convenience functions.  Debug gives us output if debug=1. &read_one_line 
# just opens files and returns one line, with trailing new lines removed.
#  
##########################################################################

# print a message if debugging is enabled
sub debug {
    if (param('debug')) {
        print "$_[0]\n";
    }
}

# computes the MD5 sum of the arument
sub md5sum {

    local $md5 = Digest::MD5->new;
    $md5->add($_[0]);
    return $md5->hexdigest; 
}

# write a string to a file
sub write_file {
    my ($filename, $content) = @_;
    open(GENERIC_FH, $filename)
        or ( &debug("Can't open $filename for writing.") && die ); 
    print GENERIC_FH $content;
    close(GENERIC_FH);
}

# read the content of a file
sub read_one_line {
    open(GENERIC_FH, $_[0])
       or ( &debug("Can't open $_[0]."), die );
    $this_line = <GENERIC_FH>;
    close(GENERIC_FH);
    chomp $this_line;

    return $this_line;
}

