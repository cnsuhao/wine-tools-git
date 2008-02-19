#!/usr/bin/perl

# Helper script - parse the results of wrc --verify-translation
# and store then in $2/langs/* and $2/dumps/*

die "This helper script takes two arguments" unless ($#ARGV == 1);

$workdir = $ARGV[1];

$type=-1;
$types[1] = "CURSOR";
$types[2] = "BITMAP";
$types[3] = "ICON";
$types[4] = "MENU";
$types[5] = "DIALOG";
$types[6] = "STRINGTABLE";
$types[7] = "FONTDIR";
$types[8] = "FONT";
$types[9] = "ACCELERATOR";
$types[10] = "RCDATA";
$types[11] = "MESSAGE";
$types[12] = "GROUP_CURSOR";
$types[14] = "GROUP_ICON";
$types[16] = "VERSION";
$types[260] = "MENUEX";
$types[262] = "DIALOGEX";

sub resource_name {
    my $type = shift @_;
    my $name = shift @_;
    
#    if ($type == 6) {
#        return "STRINGTABLE #".$name." (strings ".($name*16-16)."..".($name*16-1).")";
#    }
#    print "arg1=$type arg2=$name\n";
    if (defined($types[$type])) {
        $typename = $types[$type];
    } else {
        $typename = $type."";
    }
    return "$typename ".$name;
};

sub resource_name2 {
    $args = shift @_;
    return resource_name(split(/ /, $args));
};

sub collapse {
    my($name) = shift @_;
    $base_name = $name;
    $base_name =~ s/:[0-9a-f][0-9a-f]/:00/;
    if (not exists $tab_should_collapse{$name})
    {
        open(NAMEFILE, "<conf/$base_name");
        $content = <NAMEFILE>;
        close(NAMEFILE);
        if ($content =~  /\[ignore-sublang\]/) {
            $tab_should_collapse{$name} = TRUE;
        } else {
            open(NAMEFILE, "<conf/$name");
            $content = <NAMEFILE>;
            if ($content eq "collapse") {
                $tab_should_collapse{$name} = TRUE;
            } else {
                $tab_should_collapse{$name} = FALSE;
            }
            close(NAMEFILE);
        }

    }
    
    if ($tab_should_collapse{$name} eq TRUE) {
        $name = $base_name;
    }
    return $name;
}

$filename = shift @ARGV;
$norm_fn = $filename;
$norm_fn =~ s/[^a-zA-Z0-9]/-/g;
mkdir "$workdir/dumps/$norm_fn";

@file_langs = ("009:01");
#$deflangs{"009:00"} = TRUE;
$deflangs{"009:01"} = TRUE;

while (<STDIN>)
{
    if (m/^TYPE NEXT/)
    {
        $type++;
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
        $notransl{$type." ".$resource} = TRUE;
        next;
    }
    
    if (m/^EXIST ([0-9a-f]{3}:[0-9a-f]{2})/)
    {
        $lang = collapse($1);
        if (not defined $deflangs{$lang})
        {
            $deflangs{$lang} = TRUE;
            push @file_langs, $lang;
        }
        $reslangs{$type." ".$resource}{$lang} = TRUE;
        $transl_count{$lang}++;
        next;
    }
    
    if (m/^DIFF ([0-9a-f]{3}:[0-9a-f]{2})/)
    {
        $lang = collapse($1);
        push @{$errs_rl{$type." ".$resource}{$lang}}, "Translation out of sync";
        $transl_count{$lang}--;
        $err_count{$lang}++;
        next;
    }
    
    if (m/^EXTRA ([0-9a-f]{3}:[0-9a-f]{2})/)
    {
        $lang = collapse($1);
        push @{$warns{$lang}}, "Extra resource found not available in master language: ".resource_name($type, $resource);
        if ($resources[$#resources] eq $type." ".$resource)
        {
            pop @resources;
        }
        next;
    }
    
    if (m/^DUMP ([0-9a-f]+)$/)
    {
        open(DUMPOUT, ">$workdir/dumps/$norm_fn/$lang-$type-$resource");
        print DUMPOUT $1;
        close(DUMPOUT);
        next;
    }

    print "Unparsed line $_\n";
}

foreach $resource (@resources)
{
    next if ($notransl{$resource});
    
    foreach $lang (@file_langs)
    {
        $basic_lang = $lang;
        $basic_lang=~s/:[0-9a-f][0-9a-f]/:00/;
        if (not exists $reslangs{$resource}{$lang})
        {
            if (not exists $reslangs{$resource}{$basic_lang})
            {
                if (not exists $reslangs{$resource}{"000:00"}) {
                    push @{$missing_rl{$resource}{$lang}}, "No translation";
                    $missing_count{$lang}++;
                } else
                {
                    push @{$notes_rl{$resource}{$lang}}, "Translation inherited from neutral resource";
                    $transl_count{$lang}++;
                }
            } else
            {
                push @{$notes_rl{$resource}{$lang}}, "Translation inherited from $basic_lang";
                $transl_count{$lang}++;
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

foreach $lang (@file_langs)
{
    if (-e "conf/$lang") {
        open(LANGOUT, ">>$workdir/langs/$lang");
    } else {
        open(LANGOUT, ">>$workdir/new-langs/$lang");
    }
    print LANGOUT "FILE STAT $filename ".($transl_count{$lang}+0)." ".($missing_count{$lang}+0)." ".($err_count{$lang}+0)."\n";
    
    foreach $warn (@{$warns{$lang}})
    {
        print LANGOUT "$filename: Warning: $warn\n";
    }
    
    foreach $resource (@resources)
    {
        foreach $msg (@{$errs_rl{$resource}{$lang}})
        {
            print LANGOUT "$filename: Error: resource ".resource_name2($resource).": $msg\n";
        }
        
        foreach $msg (@{$warn_rl{$resource}{$lang}})
        {
            print LANGOUT "$filename: Warning: resource ".resource_name2($resource).": $msg\n";
        }

        foreach $msg (@{$missing_rl{$resource}{$lang}})
        {
            print LANGOUT "$filename: Missing: resource ".resource_name2($resource).": $msg\n";
        }

        foreach $msg (@{$notes_rl{$resource}{$lang}})
        {
            print LANGOUT "$filename: note: resource ".resource_name2($resource).": $msg\n";
        }
    }
    close(LANGOUT);
}

opendir(DIR, "conf");
@files = grep(!/^\./, readdir(DIR));
closedir(DIR);
foreach $lang (@files) {
    next if (!($lang eq collapse($lang)));
    next if ($transl_count{"009:01"} == 0 && $transl_count{"009:00"} == 0);
    @transl = grep {$_ eq $lang} @file_langs;
    if ($#transl == -1) {
#        print "No translation for $lang\n";
        open(LANGOUT, ">>$workdir/langs/$lang");
        print LANGOUT "FILE NONE $filename 0 ".$transl_count{"009:01"}." 0\n";
        close(LANGOUT);
    }    
}