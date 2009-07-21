<?php
include_once("config.php") ;
include_once("lib.php");

$lang = validate_lang($_REQUEST['lang']);

$transl = array();
$notransl = array();
$partial = array();

function parse_file($lang)
{
    global $transl, $partial, $notransl;
    global $DATAROOT;
    if (!file_exists("$DATAROOT/langs/$lang"))
        return;

    $file = fopen("$DATAROOT/langs/$lang", "r");
    $curr_file = "";
    while ($line = fgets($file, 4096))
    {
        if (preg_match("/FILE ([A-Z]+) (.*) ([0-9]+) ([0-9]+) ([0-9]+)/", $line, $m))
        {
            $curr_file = $m[2];
            if ($m[1] == "NONE")
            {
                $notransl[$curr_file] = array($m[3], $m[4], $m[5], 0);
                continue;
            }

            if ($m[4]>0 || $m[5]>0)
            {
                $partial[$curr_file] = array($m[3], $m[4], $m[5], 0);
                continue;
            }

            $transl[$curr_file] = array($m[3], $m[4], $m[5], 0);
        }
        if (preg_match(",$curr_file: Warning: ,", $line, $m))
        {
            if (array_key_exists($curr_file, $transl))
            {
                $partial[$curr_file] = $transl[$curr_file];
                unset($transl[$curr_file]);
            }

            if (array_key_exists($curr_file, $partial)) /* should be true - warning for $notransl shouldn't happen */
                $partial[$curr_file][3]++;
        }
    }
    fclose($file);
    ksort($transl);
    ksort($partial);
    ksort($notransl);
}

function dump_table($table)
{
    global $lang;
    if (count($table) == 0) {
        echo "none";
        return;
    }
    echo "<table>\n";
    echo "<tr><th>name</th><th>translated</th><th>missing</th><th>errors</th></tr>\n";
    foreach ($table as $key => $value)
    {
        $extra = "";
        if ($value[3] > 0)
            $extra = "(<img src=\"img/icon-warning.png\" height=\"16\"> warnings: ".$value[3].")";
        echo "<tr><td>".gen_resfile_a($lang, $key).$key."</a> $extra</td>";
        echo "<td>".$value[0]."</td>";
        echo "<td>".$value[1]."</td>";
        echo "<td>".$value[2]."</td>";
        echo "</tr>";
    }
    echo "</table>\n";
}
?>

<html>
<head>
    <link rel="stylesheet" href="style.css" type="text/css">
    <meta http-equiv="Content-Type" content="text/html; charset=utf-8">
    <title><?php echo get_lang_name($lang) ?> language - Wine translations</title>
</head>

<p><?php dump_menu_root() ?> &gt; <?php dump_menu_lang($lang, FALSE)?> </p>
<div class="main">
<h1><?php echo "Language: ".get_lang_name($lang) ?></h1>

<?php
parse_file($lang);
$translations = count($partial) + count($transl);
if (preg_match("/:00/", $lang) && $translations == 0)
{
    show_sublangs($lang);
    exit();
}
?>

<div class="group">
<h2>Partially translated modules</h2>
<div class="contents">
<?php dump_table($partial) ?>
</div>
</div>
<div class="group">
<h2>Modules not translated</h2>
<div class="contents">
<?php dump_table($notransl) ?>
</div>
</div>
<div class="group">
<h2>Fully translated modules</h2>
<div class="contents">
<?php dump_table($transl) ?>
</div>
</div>

</div>
</html>
