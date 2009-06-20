#!/usr/bin/perl

# Helper script - analyze one Makefile, run wrc --verify-translation
# on resource files and call ver.pl to parse the results

use Cwd;
use File::Basename;

sub log_string
{
    my($string) = shift(@_);
    open(LOG, ">>$workdir/run.log") || die "Couldn't open run.log\n";
    print LOG $string."\n";
    close(LOG);
}

sub mycheck
{
    my($name) = shift(@_);

    if ($name =~ m/version.rc$/) {
        print "--- Ignoring ".$name."\n" unless (exists $ENV{"NOVERBOSE"});
        return;
    }

    if (not exists $ENV{"NOVERBOSE"}) {
        print "*** ".$name."\n";
    }

    # files in dlls/ are compiled with __WINESRC__    
    my($defs) = "";
    $defs = "-D__WINESRC__" if ($name =~ m,^${srcdir}/?dlls,);

    log_string("*** $name [$defs]");

    my($respath) = dirname($name);
    my $srcincl = "-I$respath -I$srcdir/include -I$srcdir/dlls/user32";
    (my $objincl = $srcincl) =~ s!I$srcdir!I$objdir!g;
    $ret = system("$wrc $srcincl $objincl --verify-translation $defs $name $workdir/tmp.res 2>>$workdir/run.log >$workdir/ver.txt");
    if ($ret == 0)
    {
        $name =~ s,$srcdir/,,;
        if ($name eq "dlls/kernel32/kernel.rc") {
            system("$scriptsdir/ver.pl \"$name\" \"$workdir\" nonlocale $scriptsdir <$workdir/ver.txt");
            log_string("*** $name [$defs] (locale run)");
            system("$scriptsdir/ver.pl \"$name\" \"$workdir\" locale $scriptsdir <$workdir/ver.txt");
        } else {
            system("$scriptsdir/ver.pl \"$name\" \"$workdir\" normal $scriptsdir <$workdir/ver.txt");
        }
        $norm_fn= $name;
        $norm_fn =~ s/\.rc$//;
        $norm_fn =~ s/[^a-zA-Z0-9]/-/g;
        $ret = system("$wrc $srcincl $objincl $defs $srcdir/$name $workdir/dumps/res/$norm_fn.res 2>>$workdir/run.log >/dev/null");
        if ($ret != 0)
        {
            print "!!!!!!! 2nd pass return value: ".$ret."\n";        
        }
    }
    else
    {
        print "!!!!!!! return value: ".$ret."\n";
    }
}

# if PREPARE_TREES is 1 in the config file this will make the *.res file to make
# sure all the dependancies are built.
sub prepare_file
{
    my($dir) = shift (@_);
    my($file) = shift (@_);
    $file =~ s/\.rc/\.res/;
    if (($ret = system("make -C \"$dir\" \"$file\" >/dev/null 2>>$workdir/run.log")) != 0)
    {
        print "!!!!!!! make return value: ".$ret."\n";
    }
}

if ($ARGV[0] =~ m,programs/winetest/, || $ARGV[0] =~ m,/tests/,)
{
    if (not exists $ENV{"NOVERBOSE"})
    {
        print "--- Ignoring: ".$ARGV[0]."\n";
    }
    exit;
}
     
srand();
# Parse config file
open(CONFIG, "<config");
while (<CONFIG>)
{
    if (m/^([A-Z_]+)=([^\s]+)\s*$/)
    {
        $CONFIG{$1} = $2;
    }
    elsif (!(m/^#/ || m/^$/))
    {
        print("checkmakefile.pl: Can't parse config line: $_\n");
    }
}
close(CONFIG);

$srcdir = $CONFIG{"SOURCEROOT"};
$objdir = $CONFIG{"BUILDROOT"} || $srcdir;
$wrc = ($CONFIG{"WRCROOT"} || $objdir) . "/tools/wrc/wrc";
$workdir = $CONFIG{"WORKDIR"};
$scriptsdir = $CONFIG{"SCRIPTSDIR"} || ".";

if ($srcdir eq "" || $wrc eq "/tools/wrc/wrc" || $workdir eq "")
{
    die("Config entry for SOURCEROOT, WRCROOT or WORKDIR missing\n");
}

# parse the makefile
open(MAKEFILE, "<".$ARGV[0]);
$ARGV[0] =~ m,^(.*/)[^/]*$,;
$path = $1;
while (<MAKEFILE>)
{
    if (m/^RC_SRCS *=/)
    {
        while (m/\\$/)
        {
            chop;
            chop;
            $_ .= <MAKEFILE>;
        }
        m/^RC_SRCS *=(.*)$/;
        @file = split(/ /, $1);
        foreach (@file)
        {
            next if ($_ eq "");
            s/\s//;
            &prepare_file("$path", "$_") if ($CONFIG{"PREPARE_TREES"} == 1);
            &mycheck("$path$_");
        }
        exit;
    }
}
