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
    my($dir) = shift(@_);
    my($name) = shift(@_);

    if ($name =~ m/version.rc$/) {
        print "--- Ignoring ".$name."\n" unless (exists $ENV{"NOVERBOSE"});
        return;
    }

    if (not exists $ENV{"NOVERBOSE"}) {
        print "*** $dir$name\n";
    }

    # files in dlls/ are compiled with __WINESRC__    
    my($defs) = "";
    $defs = "-D__WINESRC__" if ($dir =~ m,^dlls,);

    log_string("*** $dir$name [$defs]");

    my $srcincl = "-I$srcdir/$dir -I$srcdir/include";
    (my $objincl = $srcincl) =~ s!I$srcdir!I$objdir!g;
    my $norm_fn = $dir.$name;
    $norm_fn =~ s/\.rc$//;
    $norm_fn =~ s/[^a-zA-Z0-9]/-/g;
    (my $target = $name) =~ s/.rc$/.res/;
    $ret = system("make -C $objdir/$dir -s $target 2>>$workdir/run.log && cp $objdir/$dir/$target $workdir/dumps/res/$norm_fn.res");
    if ($ret)
    {
        log_string "make -C $objdir/$dir -s $target 2>>$workdir/run.log && cp $objdir/$dir/$target $workdir/dumps/res/$norm_fn.res";
        print "!!!!!!! return value: $ret\n";
        exit 1;
    }

    $ret = system("$wrc $srcincl $objincl --verify-translation $defs $srcdir/$dir$name $workdir/tmp.res 2>>$workdir/run.log >$workdir/ver.txt");
    if ($ret == 0)
    {
        if ("$dir$name" eq "dlls/kernel32/kernel.rc") {
            system("$scriptsdir/ver.pl \"$dir$name\" \"$workdir\" nonlocale $scriptsdir <$workdir/ver.txt");
            log_string("*** $name [$defs] (locale run)");
            system("$scriptsdir/ver.pl \"$dir$name\" \"$workdir\" locale $scriptsdir <$workdir/ver.txt");
        } else {
            system("$scriptsdir/ver.pl \"$dir$name\" \"$workdir\" normal $scriptsdir <$workdir/ver.txt");
        }
    }
    else
    {
        log_string "$wrc $srcincl $objincl --verify-translation $defs $srcdir/$dir$name $workdir/tmp.res 2>>$workdir/run.log >$workdir/ver.txt";
        print "!!!!!!! return value: $ret\n";
        exit 1;
    }
}

srand();
# Parse config file
if (-f config)
{
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
}

while (@ARGV && $ARGV[0] =~ /^-/)
{
    my $opt = shift @ARGV;
    if ($opt eq "-S") { $srcdir = shift @ARGV; }
    elsif ($opt eq "-T") { $objdir = shift @ARGV; }
    elsif ($opt eq "-s") { $scriptsdir = shift @ARGV; }
    elsif ($opt eq "-t") { $toolsdir = shift @ARGV; }
    elsif ($opt eq "-w") { $workdir = shift @ARGV; }
    else
    {
        print STDERR "Usage: $0 [options] [makefiles]\n\n";
        print STDERR "  -S dir   Set the top of the Wine source tree\n";
        print STDERR "  -T dir   Set the top of the Wine build tree\n";
        print STDERR "  -t dir   Set the Wine tools directory\n";
        print STDERR "  -s dir   Set the scripts directory\n";
        print STDERR "  -w dir   Set the work directory\n";
        exit 1;
    }
}

$srcdir ||= $CONFIG{"SOURCEROOT"};
$objdir ||= $CONFIG{"BUILDROOT"} || $srcdir;
$toolsdir ||= $CONFIG{"WRCROOT"} || $objdir;
$workdir ||= $CONFIG{"WORKDIR"};
$scriptsdir ||= $CONFIG{"SCRIPTSDIR"} || ".";
$wrc = $toolsdir . "/tools/wrc/wrc";

if ($srcdir eq "" || $wrc eq "/tools/wrc/wrc" || $workdir eq "")
{
    die("Config entry for SOURCEROOT, WRCROOT or WORKDIR missing\n");
}

@makefiles = @ARGV;
if (!@makefiles)
{
    @makefiles = split(/\s/,`find $srcdir/ -name Makefile.in -print`);
}

# parse the makefiles
foreach my $makefile (@makefiles)
{
    next unless $makefile =~ m,^$srcdir/(.*/)Makefile.in$,;
    my $path = $1;
    if ($path eq "programs/winetest/" || $path =~ m,/tests/$,)
    {
        if (not exists $ENV{"NOVERBOSE"})
        {
            print "--- Ignoring: ".$path."Makefile.in\n";
        }
        next;
    }

    open(MAKEFILE, "<$makefile") or die "cannot open $makefile";
    while (<MAKEFILE>)
    {
        last if m/EXTRARCFLAGS\s*=.*res16/;  # 16-bit resources not supported
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
                &mycheck($path,$_);
            }
            last;
        }
    }
    close MAKEFILE;
}
