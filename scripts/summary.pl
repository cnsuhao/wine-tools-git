#!/usr/bin/perl

# Helper script - create a summary for each language about how
# many resources are translated

die "This helper script take one argument" unless ($#ARGV == 0);

$workdir = $ARGV[0];

sub collapse {
    my($name) = shift @_;
    if (not exists $tab_should_collapse{$name})
    {
        open(NAMEFILE, "<conf/$name");
        $content = <NAMEFILE>;
        if ($content eq "collapse") {
            $tab_should_collapse{$name} = TRUE;
        } else {
            $tab_should_collapse{$name} = FALSE;
        }
        close(NAMEFILE);
    }
    
    if ($tab_should_collapse{$name} eq TRUE) {
        $name =~ s/:[0-9a-f][0-9a-f]/:00/;
    }
    return $name;
}

opendir(DIR, "conf");
@files = grep(!/^\./, readdir(DIR));
closedir(DIR);

open(OUT, ">$workdir/langs/summary");
foreach $lang (@files) {
    next if (!($lang eq collapse($lang)));
    $transl = 0;
    $missing = 0;
    $errors = 0;
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
    $sum = $transl + $missing + $errors;
    print OUT "LANG $lang $sum $transl $missing $errors\n";
}
close(OUT);