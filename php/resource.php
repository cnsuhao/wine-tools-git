<?php
include("config.php");
include("lib.php");

$lang = validate_lang($_REQUEST['lang']);
$resfile = $_REQUEST['resfile'];
$type = $_REQUEST['type'];
$id = $_REQUEST['id'];
    
$norm_fn = preg_replace("/[^A-Za-z0-9]/", "-", $resfile);
$file = fopen("$DATAROOT/dumps/$norm_fn/$lang-$type-$id", "r");
$msgs = array();
?>
<html>
<body>
<h1>File <?php echo $resfile?> - <?php echo get_lang_name($lang) ?> language - Resource <?php echo "$id ($type)"?></h1>

<table style="background-color: #f8f8ff">
<tr style="background-color: #f0f0ff"><th colspan="2">String table #<?php echo $id?></th></tr>
<?php
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
    echo "<tr><td valign=\"top\">".(($id-1)*16+$i)."</td>";
    echo "<td>";
    $left = hexdec(get_hex($content));
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
    echo "</td></tr>\n";
}
?>
</table>
</body>
</html>