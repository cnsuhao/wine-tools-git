<?php
include("../php/lib.php");
include("../php/lib_res.php");

function resource_name2($resource)
{
    $result = preg_split("/\s+/", $resource);
    return "@RES($result[0]:$result[1])";
}

function create_resfiles($dir, $check)
{
    global $objdir, $srcdir, $toolsdir, $workdir;
    global $wrc;

    $srcs = "";
    $targets = "";
    $objs = "";
    foreach (preg_split("/\s+/", $check['files']) as $file)
    {
        if (preg_match("/^\s*$/", $file))
            continue;

        if (preg_match("/version.rc$/", $file))
        {
            echo "--- $dir : Ignoring $file\n";
            continue;
        }

        if (preg_match("/.mc$/", $file))
        {
            $file .= ".rc";
            $srcs .= " $objdir/$dir/$file";
        }
        else
        {
            $srcs .= " $srcdir/$dir/$file";
        }
        $targets .= preg_replace("/\.rc$/", ".res", $file). " ";
        $objs .= "$objdir/$dir/" . preg_replace("/\.rc$/", ".res", $file) . " ";
    }
    if ($targets == "")
        return;

    $defs = $check['defines'];
    if (preg_match("/^dlls/", $dir))
        $defs .= "-D__WINESRC__";

    fwrite(STDERR, "*** $dir [$defs]\n");

    $incl = "-I$srcdir/$dir -I$objdir/$dir -I$srcdir/include -I$objdir/include";
    $norm_fn = preg_replace("/[^a-zA-Z0-9]/", "-", $dir);

    system("make -C $objdir/$dir -s $targets");
    system("$toolsdir/tools/winebuild/winebuild --resources -o $workdir/res/$norm_fn.res $objs");
}

// Parse config file
$CONFIG = array();
if (file_exists("config"))
{
    $config = fopen("config", "r");
    while ($line = fgets($config, 4096))
    {
        if (preg_match("/^([A-Z_]+)=([^\s]+)\s*$/", $line, $m))
        {
            $CONFIG[$m[1]] = $m[2];
        }
        else if (!preg_match("/(^#|^$)/", $line))
        {
            print("checkmakefile.pl: Can't parse config line: $line\n");
        }
    }
    fclose($config);
}

$srcdir = isset($CONFIG['SOURCEROOT']) ? $CONFIG['SOURCEROOT'] : "";
$objdir = isset($CONFIG['BUILDROOT']) ? $CONFIG['BUILDROOT'] : "";
$toolsdir = isset($CONFIG['WRCROOT']) ? $CONFIG['WRCROOT'] : "";
$workdir = isset($CONFIG['WORKDIR']) ? $CONFIG['WORKDIR'] : "";

$script = $argv[0];
array_shift($argv);
while (count($argv) != 0 && preg_match("/^-/", $argv[0]))
{
    $opt = array_shift($argv);
    if ($opt == "-S")
        $srcdir = array_shift($argv);
    else if ($opt == "-T")
        $objdir = array_shift($argv);
    else if ($opt == "-t")
        $toolsdir = array_shift($argv);
    else if ($opt == "-w")
        $workdir = array_shift($argv);
    else
    {
        fwrite(STDERR, "Usage: $script [options] [makefiles]\n\n");
        fwrite(STDERR, "  -S dir   Set the top of the Wine source tree\n");
        fwrite(STDERR, "  -T dir   Set the top of the Wine build tree\n");
        fwrite(STDERR, "  -t dir   Set the Wine tools directory\n");
        fwrite(STDERR, "  -w dir   Set the work directory\n");
        exit(1);
    }
}

if ($objdir == "")
    $objdir = $srcdir;
if ($toolsdir == "")
    $toolsdir = $objdir;

$wrc = "$toolsdir/tools/wrc/wrc";

if ($srcdir == "" || $wrc == "/tools/wrc/wrc" || $workdir == "")
{
    die("Config entry for SOURCEROOT, WRCROOT or WORKDIR missing\n");
}

$makefiles = array();
exec("find $srcdir/ -name Makefile.in -print", $makefiles);

// Parse the makefiles and create the .res files
$checks = array();
sort($makefiles);
foreach ($makefiles as $makefile)
{
    $path = str_replace("$srcdir/", "", dirname($makefile));
    if ($path == "programs/winetest" || $path == $srcdir || preg_match("/\/tests$/", $path))
    {
        echo "--- Ignoring: $path/Makefile.in\n";
        continue;
    }

    $defs = "";
    $files = "";
    $file = fopen("$makefile", "r") or die("Cannot open $makefile");
    while ($line = fgets($file, 4096))
    {
        while (preg_match("/\\\\$/", $line))
        {
            $line = trim($line, "\\\\\n");
            $line .= fgets($file, 4096);
        }

        if (preg_match("/EXTRARCFLAGS\s*=\s*(.*)/", $line, $m))
        {
            $defs = $m[1];
            if (preg_match("/res16/", $defs))
                break;
        }

        if (preg_match("/^(MC|RC)_SRCS\s*=\s*(.*)$/", $line, $m))
            $files .= " $m[2]";
    }
    fclose($file);

    if ($files == "")
        continue;

    $checks[$path]['defines'] = $defs;
    $checks[$path]['files'] = $files;
    create_resfiles($path, $checks[$path]);
}

// Get all the possible languages (from kernel32) and filter
// out the neutral languages.
enum_locale_names("$workdir/res/dlls-kernel32.res");
$languages = preg_grep("/:00$/", array_keys($LOCALE_NAMES), PREG_GREP_INVERT);

$file_langs = array();
$resources = array();
$allresources = array();
$errwarncount = array();
$res = array();
$resdir = "";

// enumResource callback
function res_callback($header, $file)
{
    global $MASTER_LANGUAGE;
    global $file_langs, $resources, $allresources;
    global $languages;
    global $res;
    global $errwarncount;
    global $resdir;

    $langid = sprintf("%03x:%02x", $header["language"] & 0x3ff, $header["language"] >> 10);
    $resource = $header["type"]." ".$header["name"];

    // Only include resource types that we can actually show
    if (!is_dumpable_type($header['type']))
        return;

    // We don't care about "000:00" (LANG_NEUTRAL, SUBLANG_NEUTRAL)
    if ($langid == "000:00")
        return;

    $errwarncount[$langid][$resource]['errors'] = 0;
    $errwarncount[$langid][$resource]['warnings'] = 0;

    if ($langid != $MASTER_LANGUAGE)
    {
        $file_type = $header["type"] & 0xff;
        load_resource($res, $header["type"], $header["name"], $langid, $basic_res);
        load_resource($res, $header["type"], $header["name"], $MASTER_LANGUAGE, $master_res);

        $errwarncount[$langid][$resource] = $basic_res->getcounts($master_res);

        // A .rc file can contain empty strings (""). There is however no distinction in a
        // resource file between empty strings and missing ones. The following is the only
        // exception to the rule that a translation should exist for strings that are
        // available in English (United States).
        if (($resdir == "dlls/kernel32") && ($header["type"] == 6) && ($header["name"] == 3))
        {
            // LOCALE_S1159 and LOCALE_S2359 can be empty and are to be ignored as errors
            $LOCALE_S1159 = $basic_res->GetString(8);
            $LOCALE_S2359 = $basic_res->GetString(9);
            if (!$LOCALE_S1159)
                $errwarncount[$langid][$resource]['errors']--;
            if (!$LOCALE_S2359)
                $errwarncount[$langid][$resource]['errors']--;
        }
    }

    // Don't add neutral langs (nn:00) if we have existing sublangs (nn:xx).
    // Add the sublangs instead.
    if (preg_match("/^[0-9a-f]{3}:00/", $langid))
    {
        // Find the sublangs
        $found = 0;
        $primary_lang = str_replace(":00", "", $langid);
        $sublanguages = preg_grep("/^$primary_lang/", $languages);
        foreach ($sublanguages as $language)
        {
            $file_langs[$language] = 1;
            $found = 1;
        }
        if (!$found)
        {
            $file_langs[$langid] = 1;
        }
    }
    else
    {
        $file_langs[$langid] = 1;
    }

    $resources[$langid][$resource] = 1;
    $allresources[$resource] = 1;
}

ksort($checks);
foreach (array_keys($checks) as $dir)
{
    // Clear some arrays before we start
    $file_langs = array();
    $resources = array();
    $allresources = array();
    $errwarncount = array();

    $resfile = "$workdir/res/".preg_replace("/[^a-zA-Z0-9]/", "-", $dir).".res";
    // Check if there is actually a resource file to process
    if (!file_exists($resfile))
        continue;

    // Needed in the callback function
    $resdir = $dir;

    $res = new ResFile($resfile);
    $res->enumResources("res_callback");

    // Check if there are any resources at all
    if (count($resources) == 0)
        continue;

    foreach (array_keys($LOCALE_NAMES) as $lang)
    {
        $basic_lang = preg_replace("/:[0-9a-f][0-9a-f]/", ":00", $lang);

        // Skip the neutrals
        if ($lang == $basic_lang)
            continue;

        $mastercount = count($resources["009:01"]);

        if (!isset($file_langs[$lang]) && !isset($file_langs[$basic_lang]))
        {
            $langout = fopen("$workdir/$lang", "a+");
            fwrite($langout, "FILE NONE $dir 0 $mastercount 0\n");
            fclose($langout);
            continue;
        }

        $translated = 0;
        $missing = 0;
        $errors = 0;
        $warnings = 0;

        $errors_rl = array();
        $missing_rl = array();
        $notes_rl = array();

        foreach ($allresources as $resource => $value)
        {
            if (!isset($resources[$lang][$resource]))
            {
                if (!isset($resources[$basic_lang][$resource]))
                {
                    $missing_rl[] = "$dir: Missing: resource ".resource_name2($resource).
                                    ": No translation";
                    $missing++;
                }
                else
                {
                    // $res_errors equals all errors for a resource. $errors however only
                    // shows there is an error for a resource.
                    $res_errors = $errwarncount[$basic_lang][$resource]['errors'];
                    $res_warnings = $errwarncount[$basic_lang][$resource]['warnings'];

                    if ($res_errors)
                    {
                        $errors_rl[] = "$dir: Error: resource ".resource_name2($resource).
                                     ": Translation inherited from @LANG($basic_lang): translation out of sync";
                        $errors++;
                    }
                    else
                    {
                        $notes_rl[] = "$dir: note: resource ".resource_name2($resource).
                                      ": Translation inherited from @LANG($basic_lang)";
                        $translated++;
                    }
                }
            }
            else
            {
                $res_errors = $errwarncount[$lang][$resource]['errors'];
                $res_warnings = $errwarncount[$lang][$resource]['warnings'];

                if ($res_errors)
                {
                    $errors_rl[] = "$dir: Error: resource ".resource_name2($resource).
                                 ": Translation out of sync";
                    $errors++;
                }
                else
                {
                    $notes_rl[] = "$dir: note: resoure ".resource_name2($resource).
                                  ": Resource translated";
                    $translated++;
                }
            }
        }

        $langout = fopen("$workdir/$lang", "a+");
        fwrite($langout, "FILE STAT $dir $translated $missing $errors\n");
        foreach ($errors_rl as $msg)
            fwrite($langout, "$msg\n");
        foreach ($missing_rl as $msg)
            fwrite($langout, "$msg\n");
        foreach ($notes_rl as $msg)
            fwrite($langout, "$msg\n");
        fclose($langout);
    }
}

// Create the summary file
$summary = fopen("$workdir/summary", "w");
foreach ($languages as $lang)
{
    $transl = 0;
    $missing = 0;
    $errors = 0;
    $file = fopen("$workdir/$lang", "r");
    while ($line = fgets($file, 4096))
    {
        if (preg_match("/^FILE [A-Z]+ .* ([0-9]+) ([0-9]+) ([0-9]+)$/", $line, $m))
        {
            $transl += $m[1];
            $missing += $m[2];
            $errors += $m[3];
        }
    }
    fclose($file);
    $sum = $transl + $missing + $errors;
    fwrite($summary, "LANG $lang $sum $transl $missing $errors\n");
}
fclose($summary);
?>
