<?php
require("lib.php");
require("lib_res.php");

function resource_name2($resource)
{
    $result = preg_split("/\s+/", $resource);
    return "@RES($result[0]:$result[1])";
}

function create_resfiles($dir, $files)
{
    global $objdir, $toolsdir, $workdir;

    $targets = "";
    $objs = "";
    foreach (preg_split("/\s+/", $files) as $file)
    {
        if (preg_match("/^\s*$/", $file))
            continue;

        if (preg_match("/version.rc$/", $file))
        {
            echo "--- $dir : Ignoring $file\n";
            continue;
        }

        $targets .= preg_replace("/\.[mr]c$/", ".res", $file). " ";
        $objs .= "$objdir/$dir/" . preg_replace("/\.[mr]c$/", ".res", $file) . " ";
    }
    if ($targets == "")
        return;

    fwrite(STDERR, "*** $dir\n");

    $norm_fn = preg_replace("/[^a-zA-Z0-9]/", "-", $dir);

    system("make -C $objdir/$dir -s $targets");
    system("$toolsdir/tools/winebuild/winebuild --resources -o $workdir/res/$norm_fn.res $objs");
}

$script = $argv[0];
array_shift($argv);
while (count($argv) != 0 && preg_match("/^-/", $argv[0]))
{
    $opt = array_shift($argv);
    if ($opt == "-T")
        $objdir = array_shift($argv);
    else if ($opt == "-t")
        $toolsdir = array_shift($argv);
    else if ($opt == "-w")
        $workdir = array_shift($argv);
    else
    {
        fwrite(STDERR, "Usage: $script [options] [makefiles]\n\n");
        fwrite(STDERR, "  -T dir   Set the top of the Wine build tree\n");
        fwrite(STDERR, "  -t dir   Set the Wine tools directory\n");
        fwrite(STDERR, "  -w dir   Set the work directory\n");
        exit(1);
    }
}

if ($toolsdir == "")
    $toolsdir = $objdir;

if ($objdir == "" || $toolsdir == "" || $workdir == "")
{
    die("Config entry for BUILDROOT, WRCROOT or WORKDIR missing\n");
}

$makefiles = array();
exec("find $objdir/ -name Makefile -print", $makefiles);

// Parse the makefiles and create the .res files
$checks = array();
sort($makefiles);
foreach ($makefiles as $makefile)
{
    $path = str_replace("$objdir/", "", dirname($makefile));
    if ($path == "programs/winetest" || $path == $objdir || preg_match("/\/tests$/", $path))
    {
        echo "--- Ignoring: $path/Makefile\n";
        continue;
    }

    $files = "";
    $file = fopen("$makefile", "r") or die("Cannot open $makefile");
    while ($line = fgets($file, 4096))
    {
        while (preg_match("/\\\\$/", $line))
        {
            $line = trim($line, "\\\\\n");
            $line .= fgets($file, 4096);
        }

        if (preg_match("/EXTRARCFLAGS\s*=.*res16/", $line))
            break;

        if (preg_match("/^(MC|RC)_SRCS\s*=\s*(.*)$/", $line, $m))
            $files .= " $m[2]";
    }
    fclose($file);

    if ($files == "")
        continue;

    $checks[$path] = 1;
    create_resfiles($path, $files);
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
        // resource file between empty strings and missing ones. The following are the only
        // exception to the rule that a translation should exist for strings that are
        // available in English (United States) and vice versa.
        if (($resdir == "dlls/kernel32") && ($header["type"] == 6))
        {
            // STRINGTABLE => (string_pos => (empty=0 or non-empty=1), ...)
            $exceptions = array(
                                3 => array( 8 => 0,     // LOCALE_S1159
                                            9 => 0),    // LOCALE_S2359
                                6 => array( 0 => 1),    // LOCALE_SPOSITIVESIGN
                              257 => array(14 => 1,     // LOCALE_SMONTHNAME13
                                           15 => 1)     // LOCALE_SABBREVMONTHNAME13
                               );

            if (array_key_exists($header["name"], $exceptions))
            {
                foreach ($exceptions[$header["name"]] as $string_pos => $expect)
                {
                    $string = $basic_res->GetString($string_pos);
                    if (!!$string == $expect)
                    {
                        $errwarncount[$langid][$resource]['errors']--;
                        $errwarncount[$langid][$resource]['warnings']--;
                    }
                }
            }
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
            fwrite($langout, "FILE NONE $dir 0 $mastercount 0 0 0 0\n");
            fclose($langout);
            continue;
        }

        $translated = 0;
        $missing = 0;
        $errors = 0;
        $total_errors = 0;
        $warnings = 0;
        $total_warnings = 0;

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
                                    ": No translation (0 0)";
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
                                     ": Translation inherited from @LANG($basic_lang): translation out of sync ($res_errors $res_warnings)";
                        $errors++;
                    }
                    else
                    {
                        $notes_rl[] = "$dir: note: resource ".resource_name2($resource).
                                      ": Translation inherited from @LANG($basic_lang) ($res_errors $res_warnings)";
                        $translated++;
                    }

                    if ($res_warnings)
                        $warnings++;
                }
            }
            else
            {
                $res_errors = $errwarncount[$lang][$resource]['errors'];
                $res_warnings = $errwarncount[$lang][$resource]['warnings'];

                if ($res_errors)
                {
                    $errors_rl[] = "$dir: Error: resource ".resource_name2($resource).
                                 ": Translation out of sync ($res_errors $res_warnings)";
                    $errors++;
                }
                else
                {
                    $notes_rl[] = "$dir: note: resource ".resource_name2($resource).
                                  ": Resource translated ($res_errors $res_warnings)";
                    $translated++;
                }

                if ($res_warnings)
                    $warnings++;
            }

            $total_errors += $res_errors;
            $total_warnings += $res_warnings;
        }

        $langout = fopen("$workdir/$lang", "a+");
        fwrite($langout, "FILE STAT $dir $translated $missing $errors $total_errors $warnings $total_warnings\n");
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
    $total_errors = 0;
    $warnings = 0;
    $total_warnings = 0;
    $file = fopen("$workdir/$lang", "r");
    while ($line = fgets($file, 4096))
    {
        if (preg_match("/^FILE [A-Z]+ .* ([0-9]+) ([0-9]+) ([0-9]+) ([0-9]+) ([0-9]+) ([0-9]+)$/", $line, $m))
        {
            $transl += $m[1];
            $missing += $m[2];
            $errors += $m[3];
            $total_errors += $m[4];
            $warnings += $m[5];
            $total_warnings += $m[6];
        }
    }
    fclose($file);
    $sum = $transl + $missing + $errors;
    fwrite($summary, "LANG $lang $sum $transl $missing $errors $total_errors $warnings $total_warnings\n");
}
fclose($summary);
?>
