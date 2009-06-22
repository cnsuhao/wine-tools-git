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

sub shell($)
{
    my $cmd = shift;
    my $ret = system $cmd;
    if ($ret)
    {
        log_string $cmd;
        print "!!!!!!! return value: $ret\n";
        exit 1;
    }
}

sub mycheck
{
    my($dir) = shift(@_);
    my($defs) = shift(@_);
    my @files = @_;

    if (not exists $ENV{"NOVERBOSE"}) {
        print "*** $dir\n";
    }

    my @rcfiles;
    foreach my $f (@files)
    {
        next if $f =~ m/^\s*$/;
        if ($f =~ m/version.rc$/) {
            print "--- Ignoring ".$files[$i]."\n" unless (exists $ENV{"NOVERBOSE"});
            next;
        }
        push @rcfiles, $f;
    }
    return unless @rcfiles;

    # files in dlls/ are compiled with __WINESRC__    
    $defs .= " -D__WINESRC__" if ($dir =~ m,^dlls,);

    log_string("*** $dir [$defs]");

    my $incl = "-I$srcdir/$dir -I$objdir/$dir -I$srcdir/include -I$objdir/include";
    my $norm_fn = $dir;
    $norm_fn =~ s/[^a-zA-Z0-9]/-/g;

    my $targets = join( " ", map { (my $ret = $_) =~ s/.rc$/.res/; $ret; } @rcfiles );
    my $srcs = join( " ", map { "$srcdir/$dir/$_"; } @rcfiles );
    my $objs = join( " ", map { (my $ret = "$objdir/$dir/$_") =~ s/.rc$/.res/; $ret; } @rcfiles );

    shell "make -C $objdir/$dir -s $targets 2>>$workdir/run.log";
    shell "$toolsdir/tools/winebuild/winebuild --resources -o $workdir/dumps/res/$norm_fn.res $objs 2>>$workdir/run.log";
    shell "$wrc $incl --verify-translation $defs $srcs >$workdir/ver.txt 2>>$workdir/run.log";

    if ("$dir" eq "dlls/kernel32") {
        shell "$scriptsdir/ver.pl \"$dir\" \"$workdir\" nonlocale $scriptsdir <$workdir/ver.txt";
        log_string("*** $name [$defs] (locale run)");
        shell "$scriptsdir/ver.pl \"$dir\" \"$workdir\" locale $scriptsdir <$workdir/ver.txt";
    } else {
        shell "$scriptsdir/ver.pl \"$dir\" \"$workdir\" normal $scriptsdir <$workdir/ver.txt";
    }
}

srand();
# Parse config file
if (-f "config")
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
    next unless $makefile =~ m,^$srcdir/(.*)/Makefile.in$,;
    my $path = $1;
    if ($path eq "programs/winetest" || $path =~ m,/tests$,)
    {
        if (not exists $ENV{"NOVERBOSE"})
        {
            print "--- Ignoring: $path/Makefile.in\n";
        }
        next;
    }

    my $defs = "";
    open(MAKEFILE, "<$makefile") or die "cannot open $makefile";
    while (<MAKEFILE>)
    {
        if (m/EXTRARCFLAGS\s*=\s*(.*)/)
        {
            $defs = $1;
            last if ($defs =~ /res16/);  # 16-bit resources not supported
        }
        if (m/^RC_SRCS *=/)
        {
            while (m/\\$/)
            {
                chop;
                chop;
                $_ .= <MAKEFILE>;
            }
            m/^RC_SRCS\s*=\s*(.*)$/;
            my @files = split(/\s+/, $1);
            &mycheck($path,$defs,@files);
            last;
        }
    }
    close MAKEFILE;
}
