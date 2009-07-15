#!/usr/bin/perl -w

# Helper script - analyze all Makefiles, run wrc --verify-translation
# on resource files and parse the results

use strict;
use Cwd;
use File::Basename;

# configuration parameters
my (%CONFIG, $srcdir, $objdir, $toolsdir, $workdir, $scriptsdir, $wrc);

sub shell($)
{
    my $cmd = shift;
    my $ret = system $cmd;
    if ($ret)
    {
        print STDERR "$cmd\n";
        print "!!!!!!! return value: $ret\n";
        exit 1;
    }
}

sub mode_skip
{
    my ($mode, $type) = @_;
    return 0 if ($mode eq "normal");
    return ($type != 6) if ($mode eq "locale");
    return ($type == 6) if ($mode eq "nonlocale");
    die("Unknown mode");
}

sub resource_name
{
    my ($type, $name) = @_;

    return "\@RES($type:$name)";
}

sub resource_name2
{
    my ($args) = shift @_;
    return resource_name(split(/ /, $args));
}

my %tab_should_collapse = ();
sub collapse
{
    my($name) = shift @_;
    my $base_name = $name;
    $base_name =~ s/:[0-9a-f]{2}/:00/;
    if (not exists $tab_should_collapse{$name})
    {
        $tab_should_collapse{$name} = 0;
        if (-e "$scriptsdir/conf/$base_name")
        {
            open(NAMEFILE, "<$scriptsdir/conf/$base_name");
            my $content = <NAMEFILE>;
            close(NAMEFILE);
            if ($content =~  /\[ignore-sublang\]/)
            {
                $tab_should_collapse{$name} = 1;
            }
        }
    }

    if ($tab_should_collapse{$name} == 1)
    {
        $name = $base_name;
    }
    return $name;
}

my @languages = ();
sub mycheck
{
    my($mode, $dir, $defs, @files) = @_;

    if (not exists $ENV{"NOVERBOSE"}) {
        print "*** $dir ($mode run)\n";
    }

    my @rcfiles;
    my @srcs;
    foreach my $f (@files)
    {
        next if $f =~ m/^\s*$/;
        if ($f =~ m/version.rc$/) {
            print "--- Ignoring $f\n" unless (exists $ENV{"NOVERBOSE"});
            next;
        }
        if ($f =~ m/.mc$/)
        {
            $f .= ".rc";
            push @srcs, "$objdir/$dir/$f";
        }
        else
        {
            push @srcs, "$srcdir/$dir/$f";
        }
        push @rcfiles, $f;
    }
    return unless @rcfiles;

    # files in dlls/ are compiled with __WINESRC__    
    $defs .= " -D__WINESRC__" if ($dir =~ m,^dlls,);

    print STDERR "*** $dir [$defs]\n";

    my $incl = "-I$srcdir/$dir -I$objdir/$dir -I$srcdir/include -I$objdir/include";
    my $norm_fn = $dir;
    $norm_fn =~ s/[^a-zA-Z0-9]/-/g;

    my $targets = join( " ", map { (my $ret = $_) =~ s/.rc$/.res/; $ret; } @rcfiles );
    my $srcs = join( " ", @srcs );
    my $objs = join( " ", map { (my $ret = "$objdir/$dir/$_") =~ s/.rc$/.res/; $ret; } @rcfiles );

    shell "make -C $objdir/$dir -s $targets";
    shell "$toolsdir/tools/winebuild/winebuild --resources -o $workdir/dumps/res/$norm_fn.res $objs";

    my $type = -1;
    my $resource;
    my %deflangs = ();
    my @file_langs = ();
    my %reslangs = ();

    @file_langs = ("009:01");
    $deflangs{"009:01"} = 1;

    my @resources = ();

    my %transl_count = ();
    my %notransl = ();
    my %err_count = ();
    my %errs_rl = ();
    my %warns = ();

    open(VERIFY, "$wrc $incl --verify-translation $defs $srcs|");
    while (<VERIFY>)
    {
        if (m/^TYPE NEXT/)
        {
            $type++;
            next;
        }

        if (mode_skip($mode, $type))
        {
            next;
        }

        if (m/^RESOURCE \[([a-zA-Z_0-9.]+)\]/)
        {
            $resource = $1;
            push @resources, $type." ".$resource;
            next;
        }

        if (m/^NOTRANSL/)
        {
            $notransl{$type." ".$resource} = 1;
            next;
        }

        if (m/^EXIST ([0-9a-f]{3}:[0-9a-f]{2})/)
        {
            my $lang = collapse($1);

            # Don't add neutral langs (nn:00) to the file_langs array
            # if we have sublangs (nn:xx) in the conf directory, add
            # it's sublangs instead (if present).
            #
            # English:Neutral (009:00) is an exception to this rule.
            #
            if (($lang =~ /^[0-9a-f]{3}:00/) && ($lang ne "009:00"))
            {
                # Find the sublangs
                my $primary_lang = $lang;
                $primary_lang =~ s/:00//;
                my $found = 0;
                foreach my $language (@languages)
                {
                    if ($language =~ /$primary_lang:./)
                    {
                        if (not defined $deflangs{$language})
                        {
                            $deflangs{$language} = 1;
                            push @file_langs, $language;
                        }
                        $found = 1;
                    }
                }
                if ((!$found) && (not defined $deflangs{$lang}))
                {
                    $deflangs{$lang} = 1;
                    push @file_langs, $lang;
                }
            }
            elsif (not defined $deflangs{$lang})
            {
                $deflangs{$lang} = 1;
                push @file_langs, $lang;
            }
            $reslangs{$type." ".$resource}{$lang} = 1;
            $transl_count{$lang}++;
            next;
        }

        if (m/^DIFF ([0-9a-f]{3}:[0-9a-f]{2})/)
        {
            my $lang = collapse($1);
            push @{$errs_rl{$type." ".$resource}{$lang}}, "Translation out of sync";
            $transl_count{$lang}--;
            $err_count{$lang}++;
            next;
        }

        if (m/^EXTRA ([0-9a-f]{3}:[0-9a-f]{2})/)
        {
            my $lang = collapse($1);
            push @{$warns{$lang}}, "Extra resource found not available in master language: ".resource_name($type, $resource);
            if ($resources[$#resources] eq $type." ".$resource)
            {
                pop @resources;
            }
            next;
        }

        if (m/^DUMP ([0-9a-f]+)$/)
        {
            next;
        }

        print "Unparsed line $_\n";
    }
    close(VERIFY);

    my %missing_rl;
    my %notes_rl;
    my %warn_rl;
    my %missing_count;

    foreach $resource (@resources)
    {
        next if ($notransl{$resource});

        foreach my $lang (@file_langs)
        {
            my $basic_lang = $lang;
            $basic_lang=~s/:[0-9a-f][0-9a-f]/:00/;
            if (not exists $reslangs{$resource}{$lang})
            {
                if (not exists $reslangs{$resource}{$basic_lang})
                {
                    if (not exists $reslangs{$resource}{"000:00"}) {
                        push @{$missing_rl{$resource}{$lang}}, "No translation";
                        $missing_count{$lang}++;
                    }
                    else
                    {
                        push @{$notes_rl{$resource}{$lang}}, "Translation inherited from neutral resource";
                        $transl_count{$lang}++;
                    }
                }
                else
                {
                    if (exists $errs_rl{$resource}{$basic_lang})
                    {
                        push @{$errs_rl{$resource}{$lang}}, "Translation inherited from \@LANG($basic_lang): translation out of sync";
                        $err_count{$lang}++;
                    }
                    else
                    {
                        push @{$notes_rl{$resource}{$lang}}, "Translation inherited from \@LANG($basic_lang)";
                        $transl_count{$lang}++;
                    }
                }
            }
            else
            {
                if (not exists $errs_rl{$resource}{$lang})
                {
                    push @{$notes_rl{$resource}{$lang}}, "Resource translated";
                }
            }
        }
    }
    foreach my $lang (@file_langs)
    {
        my $suffix;

        if (!exists $transl_count{$lang}) { $transl_count{$lang} = 0; }
        if (!exists $missing_count{$lang}) { $missing_count{$lang} = 0; }
        if (!exists $err_count{$lang}) { $err_count{$lang} = 0; }

        if ($mode eq "locale")
        {
            my $basic_lang = $lang;
            $basic_lang =~ s/:[0-9a-f]{2}/:00/;
            if (-e "$scriptsdir/conf/$lang")
            {
                open(LANGOUT, ">>$workdir/langs/$lang");
            }
            elsif (-e "$scriptsdir/conf/$basic_lang")
            {
                open(LANGOUT, ">>$workdir/langs/$basic_lang");
            }
            else
            {
#                print("Ignoring locale $lang\n");
                next;
            }
            print LANGOUT "LOCALE $lang $dir ".($transl_count{$lang}+0)." ".($missing_count{$lang}+0)." ".($err_count{$lang}+0)."\n";
            $suffix = "#locale$lang";
        }
        else
        {
            if (-e "$scriptsdir/conf/$lang")
            {
                open(LANGOUT, ">>$workdir/langs/$lang");
            }
            else
            {
                open(LANGOUT, ">>$workdir/new-langs/$lang");
            }
            print LANGOUT "FILE STAT $dir ".($transl_count{$lang}+0)." ".($missing_count{$lang}+0)." ".($err_count{$lang}+0)."\n";
            $suffix = "";
        }
        foreach my $warn (@{$warns{$lang}})
        {
            print LANGOUT "$dir$suffix: Warning: $warn\n";
        }

        foreach $resource (@resources)
        {
            foreach my $msg (@{$errs_rl{$resource}{$lang}})
            {
                print LANGOUT "$dir$suffix: Error: resource ".resource_name2($resource).": $msg\n";
            }

            foreach my $msg (@{$warn_rl{$resource}{$lang}})
            {
                print LANGOUT "$dir$suffix: Warning: resource ".resource_name2($resource).": $msg\n";
            }

            foreach my $msg (@{$missing_rl{$resource}{$lang}})
            {
                print LANGOUT "$dir$suffix: Missing: resource ".resource_name2($resource).": $msg\n";
            }

            foreach my $msg (@{$notes_rl{$resource}{$lang}})
            {
                print LANGOUT "$dir$suffix: note: resource ".resource_name2($resource).": $msg\n";
            }
        }
        close(LANGOUT);
    }

    if (!($mode eq "locale"))
    {
        opendir(DIR, "$scriptsdir/conf");
        my @files = grep(!/^\./, readdir(DIR));
        closedir(DIR);
        foreach my $lang (@files)
        {
            next if (!($lang eq collapse($lang)));
            next if ($transl_count{"009:01"} == 0);
            my @transl = grep {$_ eq $lang} @file_langs;
            if ($#transl == -1)
            {
                open(LANGOUT, ">>$workdir/langs/$lang");
                print LANGOUT "FILE NONE $dir 0 ".$transl_count{"009:01"}." 0\n";
                close(LANGOUT);
            }
        }
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

# Get just the sublangs defined in the conf directory
opendir(DIR, "$scriptsdir/conf");
@languages = grep(!/(^\.|.:00)/, readdir(DIR));
closedir(DIR);

my @makefiles = @ARGV;
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
    my @files = ();
    open(MAKEFILE, "<$makefile") or die "cannot open $makefile";
    while (<MAKEFILE>)
    {
        while (m/\\$/)
        {
            chop;
            chop;
            $_ .= <MAKEFILE>;
        }
        if (m/EXTRARCFLAGS\s*=\s*(.*)/)
        {
            $defs = $1;
            last if ($defs =~ /res16/);  # 16-bit resources not supported
        }
        if (m/^(MC|RC)_SRCS\s*=\s*(.*)$/)
        {
            push @files, split(/\s+/, $2);
        }
    }
    close MAKEFILE;
    next unless @files;

    if ("$path" eq "dlls/kernel32")
    {
        mycheck("nonlocale", $path,$defs,@files);
        mycheck("locale", $path,$defs,@files);
    }
    else
    {
        mycheck("normal", $path,$defs,@files);
    }
}

# create the summary file
opendir(DIR, "$scriptsdir/conf");
my @files = grep(!/^\./, readdir(DIR));
closedir(DIR);

open(OUT, ">$workdir/langs/summary");
foreach my $lang (@files)
{
    next if (!($lang eq collapse($lang)));
    my $transl = 0;
    my $missing = 0;
    my $errors = 0;
    open(FILE, "<$workdir/langs/$lang");
    while (<FILE>)
    {
        if (m/^FILE [A-Z]+ .* ([0-9]+) ([0-9]+) ([0-9]+)$/) {
            $transl += $1;
            $missing += $2;
            $errors += $3;
        }
    }
    close(FILE);
    my $sum = $transl + $missing + $errors;
    print OUT "LANG $lang $sum $transl $missing $errors\n";
}
close(OUT);
