<?php
include_once("config.php") ;
include_once("lib.php");

$lang = validate_lang($_REQUEST['lang']);
$pedantic = isset($_REQUEST['pedantic']);

$transl = array();
$notransl = array();
$partial = array();

function parse_file($lang)
{
    global $transl, $partial, $notransl;
    global $DATAROOT;
    if (!file_exists("$DATAROOT/$lang"))
        return;

    $file = fopen("$DATAROOT/$lang", "r");
    $curr_file = "";
    while ($line = fgets($file, 4096))
    {
        if (preg_match("/FILE ([A-Z]+) (.*) ([0-9]+) ([0-9]+) ([0-9]+) ([0-9]+) ([0-9]+) ([0-9]+)/", $line, $m))
        {
            $curr_file = $m[2];
            if ($m[1] == "NONE")
            {
                $notransl[$curr_file] = array($m[3], $m[4], $m[5], $m[6], $m[7], $m[8]);
                continue;
            }

            if ($m[4]>0 || $m[5]>0)
            {
                $partial[$curr_file] = array($m[3], $m[4], $m[5], $m[6], $m[7], $m[8]);
                continue;
            }

            $transl[$curr_file] = array($m[3], $m[4], $m[5], $m[6], $m[7], $m[8]);
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
    global $pedantic;

    if (count($table) == 0) {
        echo "<div class=\"contents\">";
        echo "none";
        echo "</div>";
        return;
    }
    echo "<table>\n";
    echo "<tr>";
    // Make room for a possible icon
    if ($pedantic)
        echo "<th></th>";
    echo "<th>name</th><th>translated</th><th>missing</th><th>errors</th>\n";
    // Make room for the warning count
    if ($pedantic)
        echo "<th>warnings</th>";
    echo "</tr>\n";

    foreach ($table as $key => $value)
    {
        $extra = "";
        echo "<tr>";
        if ($pedantic)
        {
            $title = "title=\"";
            if ($value[2] > 0) $title .= "$value[3] errors in $value[2] resources";
            else $title .= "No errors";
            if ($value[4] > 0) $title .= ", $value[5] warnings in $value[4] resources";
            else $title .= ", No warnings";
            $title .= "\"";

            if ($value[2] > 0)
                echo "<td><img src=\"img/icon-error.png\" $title height=\"16\" alt=\"errors\"></td>";
            else if ($value[4] > 0)
                echo "<td><img src=\"img/icon-warning.png\" $title height=\"16\" alt=\"warnings\"></td>";
            else if ($value[1] > 0)
                echo "<td><img src=\"img/icon-missing.gif\" $title height=\"16\" alt=\"missing\"></td>";
            else
                echo "<td><img src=\"img/icon-ok.png\" height=\"16\" alt=\"ok\"></td>";
        }
        echo "<td>".gen_resfile_a($lang, $key).$key."</a> $extra</td>";
        echo "<td>".$value[0]."</td>";
        echo "<td>".$value[1]."</td>";
        echo "<td>".$value[2]."</td>";
        if ($pedantic)
            echo "<td>$value[4]</td>";
        echo "</tr>\n";
    }
    echo "</table>\n";
}
?>

<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 4.01 Transitional//EN">
<html>
<head>
    <link rel="stylesheet" href="style.css" type="text/css">
    <meta http-equiv="Content-Type" content="text/html; charset=utf-8">
    <title><?php echo get_lang_name($lang) ?> language - Wine translations</title>
</head>

<div class="navbar">
<?php dump_menu_lang($lang, FALSE); ?>
</div>
<div class="main">
<h1><?php echo "Language: ".get_lang_name($lang) ?></h1>

<?php
parse_file($lang);
$translations = count($partial) + count($transl);
if (preg_match("/:00/", $lang) && $translations == 0)
{
    echo "<div class=\"contents\">";
    show_sublangs($lang);
    echo "</div>";
    exit();
}
?>

<div class="group">
<h2>Partially translated modules</h2>
<?php dump_table($partial) ?>
</div>
<div class="group">
<h2>Modules not translated</h2>
<?php dump_table($notransl) ?>
</div>
<div class="group">
<h2>Fully translated modules</h2>
<?php dump_table($transl) ?>
</div>

</div>
</html>
