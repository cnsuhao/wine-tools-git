<?php
include("config.php");
include("lib.php");

$lang = validate_lang($_REQUEST['lang']);
$resfile = validate_resfile($_REQUEST['resfile']);

$file = fopen("$DATAROOT/langs/$lang", "r");
$msgs = array();
?>
<html>
<head>
    <link rel="stylesheet" href="style.css" type="text/css"/>
    <title>Module <?php echo $resfile?> - Wine translations</title>
</head>

<?php dump_menu_root() ?> &gt <?php dump_menu_lang($lang) ?> &gt <?php dump_menu_resfile($lang, $resfile, FALSE) ?>
<div class="main">
<h1>Module <?php echo $resfile?></h1>

<?php
warn_if_lang_hidden($lang);

while ($line = fgets($file, 4096))
{
    if (preg_match("@$resfile: (.*)@", $line, $m))
    {
        $msgs[] = $m[1];
    }
}

if (count($msgs) == 0) {
    echo "<p>This module is not translated into ".get_lang_name($lang).".</p>\n";
    echo "<ul><li>If you want to see what resources are in this module, check the "
            .gen_resfile_a($MASTER_LANGUAGE, $resfile)."English (US) version</a>"
            ." of this module</li>\n";
    echo "<li>If you want to translate this module you should check the $resfile\n";
    echo "directory in the Wine source tree and make it include a new language file for\n";
    echo get_lang_name($lang)." (see $WINE_WIKI_TRANSLATIONS for a guide to\n";
    echo "translating)</li>";
    exit();
}

echo "<table>\n";
sort($msgs);
foreach ($msgs as $value)
{
    echo "<tr><td>";
    if (strpos($value, "Error: ") === 0) {
        $icon = "error.png";
    } else if (strpos($value, "Warning: ") === 0) {
        $icon = "warning.png";
    } else if (strpos($value, "note: ") === 0) {
        $icon = "ok.png";
    } else if (strpos($value, "Missing: ") === 0) {
        $icon = "missing.gif";
    } else {
        unset($icon);
    }
    if (isset($icon))
        echo "<img src=\"img/icon-".$icon."\" width=\"32\">";

    $line_lang = $lang;
    if (preg_match("/@LANG\(([0-9a-f]{3}:[0-9a-f]{2})\)/", $value, $m))
    {
        validate_lang($m[1]);
        $line_lang = $m[1];
        $value = preg_replace("/@LANG\(([0-9a-f]{3}:[0-9a-f]{2})\)/", get_lang_name($m[1]), $value);
    }

    if (preg_match("/@RES\(([^:\)]+):([^:\)]+)\)/", $value, $m))
    {
        if (is_dumpable_type($m[1]) && (strpos($value, "Missing: ") !== 0))
        {
            $error = (strpos($value, "Error: ") === 0);
            $value = preg_replace("/@RES\(([^:\)]+):([^:\)]+)\)/", 
                gen_resource_a($line_lang, $resfile, $m[1], $m[2], $error).
                get_resource_name($m[1], $m[2])."</a>",
                $value);
        }
        else
        {
            $value = preg_replace("/@RES\(([^:\)]+):([^:\)]+)\)/", get_resource_name($m[1], $m[2]), $value);
            if (is_dumpable_type($m[1]) && (strpos($value, "Missing: ") === 0))
                $value .= " (see ".gen_resource_a($MASTER_LANGUAGE, $resfile, $m[1], $m[2])
                    .$MASTER_LANGUAGE_NAME." resource</a>)";
        }
    }
    
    if (strpos($value, "note: ") === 0)
        $value = substr($value, 6);

    echo "</td><td>".$value."</td></tr>\n";
}
?>
</div>
</html>
