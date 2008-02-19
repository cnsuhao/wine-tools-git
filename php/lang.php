<?php
include_once("config.php") ;
include_once("lib.php");

$lang = validate_lang($_REQUEST['lang']);

$file = fopen("$DATAROOT/langs/$lang", "r");
$transl = array();
$notransl = array();
$partial = array();
while ($line = fgets($file, 4096))
{
    if (preg_match("/FILE ([A-Z]+) (.*) ([0-9]+) ([0-9]+) ([0-9]+)/", $line, $m))
    {
        if ($m[1] == "NONE")
        {
            $notransl[$m[2]] = array($m[3], $m[4], $m[5], $m[2]);
            continue;
        }
        
        if ($m[4]>0 || $m[5]>0)
        {
            $partial[$m[2]] = array($m[3], $m[4], $m[5], $m[2]);
            continue;
        }
        
        $transl[$m[2]] = array($m[3], $m[4], $m[5], $m[2]);
    }
    if (preg_match("/LOCALE ([0-9a-f]{3}:[0-9a-f]{2}) (.*) ([0-9]+) ([0-9]+) ([0-9]+)/", $line, $m))
    {
        $locale["Locale data for LOCALE ".$m[1]] = array($m[3], $m[4], $m[5], $m[2]."#locale".$m[1]);
    }
}
fclose($file);
ksort($transl);
ksort($partial);
ksort($notransl);
?>
<html>
<?php
function dump_table($table)
{
    global $lang;
    if (count($table) == 0) {
        echo "none";
        return;
    }
    echo "<table border=\"1\">\n";
    echo "<tr><th>File name</th><th>translated</th><th>missing</th><th>errors</th></tr>\n";
    foreach ($table as $key => $value)
    {
        echo "<tr><td><a href=\"resfile.php?lang=$lang&resfile=".urlencode($value[3])."\">".$key."</a></td>";
        echo "<td>".$value[0]."</td>";
        echo "<td>".$value[1]."</td>";
        echo "<td>".$value[2]."</td>";
        echo "</tr>";
    }
    echo "</table>\n";
}

?>
<h1><?php echo "Language: ".get_lang_name($lang) ?></h1>
<h2>Partialy translanted files</h2>
<?php dump_table($partial) ?>

<h2>Files not translanted</h2>
<?php dump_table($notransl) ?>

<h2>Locales data</h2>
<?php dump_table($locale) ?>

<h2>Fully translated files</h2>
<?php dump_table($transl) ?>

</html>
