<?php
include("config.php");
include("lib.php");

$lang = validate_lang($_REQUEST['lang']);
$resfile = validate_resfile($_REQUEST['resfile']);
$type = validate_type($_REQUEST['type']);
$id = validate_id($_REQUEST['id']);
$compare = isset($_REQUEST['compare']);
    
$norm_fn = preg_replace("/[^A-Za-z0-9]/", "-", $resfile);
$file = fopen("$DATAROOT/dumps/$norm_fn/$lang-$type-$id", "r");
$msgs = array();
?>
<html>
<body>
<h1>File <?php echo $resfile?> - <?php echo get_lang_name($lang) ?> language - Resource <?php echo "$id ($type)"?></h1>

<table style="background-color: #f0f0ff">
<tr style="background-color: #e0e0ff"><th colspan="3">String table #<?php echo $id?></th></tr>
<?php

if (!$compare)
{
    echo "<tr style=\"background-color: #e8e8ff\"><td colspan=\"2\" style=\"text-align: right\">";
    echo "<small><a href=\"resource.php?lang=".urlencode($lang)."&resfile=".urlencode($resfile)."&type=".urlencode($type)."&id=".urlencode($id)."&compare=\">";
    echo "Compare with ".get_lang_name($MASTER_LANGUAGE)." &gt;&gt;</a></small>";
    echo "</td></tr>";
}
else
{
    $master_file = fopen("$DATAROOT/dumps/$norm_fn/$MASTER_LANGUAGE-$type-$id", "r");
    $master_content = fgets($master_file, 262144);
    fclose($master_file);

    echo "<tr style=\"background-color: #e8e8ff\"><td colspan=\"3\" style=\"text-align: right\">";
    echo "<small><a href=\"resource.php?lang=".urlencode($lang)."&resfile=".urlencode($resfile)."&type=".urlencode($type)."&id=".urlencode($id)."\">";
    echo "&lt;&lt; Hide compare with ".get_lang_name($MASTER_LANGUAGE)."</a></small>";
    echo "</td></tr>";

    echo "<tr style=\"background-color: #e8e8ff\"><td>id</td><td>".get_lang_name($lang)."</td><td>".get_lang_name($MASTER_LANGUAGE)."</td></tr>\"";
}

$content = fgets($file, 262144);

function get_hex(&$content)
{
    if (!preg_match("/^([0-9a-f]{4})/", $content, $m))
        die("Premature end of dump");

    $content = preg_replace("/^([0-9a-f]{4})/", "", $content);
    $str = $m[1];
    $hex = $str[2].$str[3].$str[0].$str[1];
    return $hex;
}

for ($i=0; $i<16; $i++) {
    $extra = "";
    
    $left = hexdec(get_hex($content));
    if ($compare)
    {
        $master_left = hexdec(get_hex($master_content));
        if ((!$master_left && $left) || ($master_left && !$left))
            $extra = " style=\"background-color: #ffb8d0\"";
    }
    
    echo "<tr$extra><td valign=\"top\">".(($id-1)*16+$i)."</td>";
    echo "<td>";

    if ($left == 0)
    {
        echo "<i style=\"color: #7f7fff\">empty</i>";
    }
    else
    {
        echo "&quot;";
        while ($left > 0)
        {
            $hex = get_hex($content);        
            echo "&#x".$hex.";";
            $left--;
        }
        echo "&quot\n";
    }

    if ($compare)
    {
        echo "</td><td>";
        $left = $master_left;
        if ($left == 0)
        {
            echo "<i style=\"color: #7f7fff\">empty</i>";
        }
        else
        {
            echo "&quot;";
            while ($left > 0)
            {
                $hex = get_hex($master_content);        
                echo "&#x".$hex.";";
                $left--;
            }
            echo "&quot\n";
        }
    }
    echo "</td></tr>\n";
}
?>
</table>
</body>
</html>