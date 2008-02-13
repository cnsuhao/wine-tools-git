<?php
include("config.php");
include("lib.php");

$lang = validate_lang($_REQUEST['lang']);
$resfile = validate_resfile($_REQUEST['resfile']);
    
$file = fopen("$DATAROOT/langs/$lang", "r");
$msgs = array();
?>
<html>
<h1>File <?php echo $resfile?> - <?php echo get_lang_name($lang) ?> language</h1>

<?php
while ($line = fgets($file, 4096))
{
    if (preg_match("@$resfile: (.*)@", $line, $m))
    {
        $msgs[] = $m[1];
    }
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
        
    if (preg_match("/STRINGTABLE ([0-9]+)/", $value, $m)) {
        $id0 = $m[1]*16 - 16;
        $id1 = $m[1]*16 - 1;
        if (strpos($value, "Missing: ") === 0)
        {
            $value = preg_replace("/STRINGTABLE ([0-9]+)/",
                "STRINGTABLE #".$m[1]." (strings $id0..$id1)",
                $value);
        }
        else
        {
            $value = preg_replace("/STRINGTABLE ([0-9]+)/",
                "<a href=\"resource.php?lang=$lang&resfile=$resfile&type=6&id=".$m[1]."\">".
                "STRINGTABLE #".$m[1]." (strings $id0..$id1)</a>",
                $value);
        }
    }
    echo "</td><td>".$value."</td></tr>\n";
}
?>
</html>