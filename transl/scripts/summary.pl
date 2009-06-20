#!/usr/bin/perl

# Helper script - create a summary for each language about how
# many resources are translated

die "This helper script takes two arguments" unless ($#ARGV == 1);

$workdir = $ARGV[0];
$scriptsdir = $ARGV[1];

sub collapse {
    my($name) = shift @_;
    $base_name = $name;
    $base_name =~ s/:[0-9a-f]{2}/:00/;
    if (not exists $tab_should_collapse{$name})
    {
        open(NAMEFILE, "<$scriptsdir/conf/$base_name");
        $content = <NAMEFILE>;
        close(NAMEFILE);
        if ($content =~  /\[ignore-sublang\]/) {
            $tab_should_collapse{$name} = TRUE;
        }
    }
    
    if ($tab_should_collapse{$name} eq TRUE) {
        $name = $base_name;
    }
    return $name;
}

opendir(DIR, "$scriptsdir/conf");
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
