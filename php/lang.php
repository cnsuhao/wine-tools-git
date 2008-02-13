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
            $notransl[$m[2]] = array($m[3], $m[4], $m[5]);
            continue;
        }
        
        if ($m[4]>0 || $m[5]>0)
        {
            $partial[$m[2]] = array($m[3], $m[4], $m[5]);
            continue;
        }
        
        $transl[$m[2]] = array($m[3], $m[4], $m[5]);
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
        echo "<tr><td><a href=\"resfile.php?lang=$lang&resfile=".urlencode($key)."\">".$key."</a></td>";
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

<h2>Fully translated files</h2>
<?php dump_table($transl) ?>

</html>
