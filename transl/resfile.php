<?php
include("config.php");
include("lib.php");

$lang = validate_lang($_REQUEST['lang']);
$resfile = validate_resfile($_REQUEST['resfile']);
$pedantic = isset($_REQUEST['pedantic']);

$msgs = array();
?>
<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 4.01 Transitional//EN">
<html>
<head>
    <link rel="stylesheet" href="style.css" type="text/css">
    <meta http-equiv="Content-Type" content="text/html; charset=utf-8">
    <title>Module <?php echo $resfile?> - Wine translations</title>
</head>

<div class="navbar">
<?php dump_menu_resfile($lang, $resfile, FALSE); ?>
</div>
<div class="main">
<h1>Module <?php echo $resfile?></h1>

<?php

if (preg_match("/:00/", $lang))
{
    echo "<div class=\"contents\">";
    show_sublangs($lang);
    echo "</div>";
    exit();
}

$file = fopen("$DATAROOT/$lang", "r");
while ($line = fgets($file, 4096))
{
    if (preg_match("@$resfile: (.*) \(([0-9]+) ([0-9]+)\)@", $line, $m))
        $msgs[] = array($m[1], $m[2], $m[3]);
}
fclose($file);

if (count($msgs) == 0)
{
    echo "<div class=\"contents\">";
    echo "<p>This module is not translated into ".get_lang_name($lang).".</p>\n";
    echo "<ul><li>If you want to see what resources are in this module, check the "
            .gen_resfile_a($MASTER_LANGUAGE, $resfile).get_locale_name($MASTER_LANGUAGE)." version</a>"
            ." of this module</li>\n";
    echo "<li>If you want to translate this module you should check the $resfile\n";
    echo "directory in the Wine source tree and make it include a new language file for\n";
    echo get_lang_name($lang)." (see $WINE_WIKI_TRANSLATIONS for a guide to\n";
    echo "translating)</li>";
    echo "</div>";
    exit();
}

echo "<table>\n";
sort($msgs);
foreach ($msgs as $value)
{
    $org_value = $value[0];
    if (strpos($value[0], "Error: ") === 0) {
        $icon = "error.png";
    } else if (strpos($value[0], "note: ") === 0) {
        $icon = "ok.png";
    } else if (strpos($value[0], "Missing: ") === 0) {
        $icon = "missing.gif";
    } else {
        unset($icon);
    }

    $line_lang = $lang;
    if (preg_match("/@LANG\(([0-9a-f]{3}:[0-9a-f]{2})\)/", $value[0], $m))
    {
        validate_lang($m[1]);
        $line_lang = $m[1];
        $value[0] = preg_replace("/@LANG\(([0-9a-f]{3}:[0-9a-f]{2})\)/", get_lang_name($m[1]), $value[0]);
    }

    if (preg_match("/@RES\(([^:\)]+):([^:\)]+)\)/", $value[0], $m))
    {
        if (is_dumpable_type($m[1]) && (strpos($value[0], "Missing: ") !== 0))
        {
            $error = (strpos($value[0], "Error: ") === 0);
            $value[0] = preg_replace("/@RES\(([^:\)]+):([^:\)]+)\)/",
                gen_resource_a($line_lang, $resfile, $m[1], $m[2], $error).
                get_resource_name($m[1], $m[2])."</a>",
                $value[0]);

            if ($pedantic && ($lang != "$MASTER_LANGUAGE"))
            {
                if ($value[2])
                {
                    if ($icon != "error.png")
                        $icon = "warning.png";
                    $value[0] .= ", there are $value[2] potential translation problems";
                }
            }
        }
        else
        {
            $value[0] = preg_replace("/@RES\(([^:\)]+):([^:\)]+)\)/", get_resource_name($m[1], $m[2]), $value[0]);
            if (is_dumpable_type($m[1]) && (strpos($value[0], "Missing: ") === 0))
                $value[0] .= " (see ".gen_resource_a($MASTER_LANGUAGE, $resfile, $m[1], $m[2])
                    .get_locale_name($MASTER_LANGUAGE)." resource</a>)";
        }
    }

    if (strpos($value[0], "note: ") === 0)
        $value[0] = substr($value[0], 6);

    echo "<tr><td>";

    if (isset($icon))
        echo "<img src=\"img/icon-".$icon."\" width=\"32\" alt=\"".$org_value."\">";

    echo "</td><td>".$value[0]."</td></tr>\n";
}
echo "</table>\n";
?>
</div>
</html>
