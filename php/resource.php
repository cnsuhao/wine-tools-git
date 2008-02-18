<?php
include("config.php");
include("lib.php");
include("lib_res.php");

$lang = validate_lang($_REQUEST['lang']);
$resfile = validate_resfile($_REQUEST['resfile']);
$type = validate_type($_REQUEST['type']);
$id = validate_id($_REQUEST['id']);
$compare = isset($_REQUEST['compare']);
    
?>
<html>
<head>
    <style>
    .resmeta
    {
        color: #7f7fff;
        font-style: italic;
    }
    </style>
</head>
<body>
<h1>File <?php echo $resfile?> - <?php echo get_lang_name($lang) ?> language - Resource <?php echo "$id ($type)"?></h1>

<?php

$resources = new ResFile(get_res_path($resfile));

$resdata = $resources->loadResource($type, $id, get_lang_binid($lang), is_lang_ignore_sublang($lang));
if (!$resdata)
    die("Resource not found in *.res file\n");
$res = new StringTable($resdata[0], $resdata[1]);

if ($compare)
{
    $resdata = $resources->loadResource($type, $id, $MASTER_LANGUAGE_BINID);
    if (!$resdata)
    {
        echo ("<b>Can't compare with master language as resource not found</b>\n");
    }
    $master_res = new StringTable($resdata[0], $resdata[1]);
}

unset($resdata);

?>

<table style="background-color: #f0f0ff">
<tr style="background-color: #e0e0ff"><th colspan="3">String table #<?php echo $id?></th></tr>
<?php

function dump_unicode_or_empty($uni_str)
{
    if ($uni_str)
        dump_unicode($uni_str);
    else
        echo "<span class=\"resmeta\">empty</span>";
}

if (!$compare)
{
    echo "<tr style=\"background-color: #e8e8ff\"><td colspan=\"2\" style=\"text-align: right\">";
    echo "<small><a href=\"resource.php?lang=".urlencode($lang)."&resfile=".urlencode($resfile)."&type=".urlencode($type)."&id=".urlencode($id)."&compare=\">";
    echo "Compare with ".$MASTER_LANGUAGE_NAME." &gt;&gt;</a></small>";
    echo "</td></tr>";
}
else
{
    echo "<tr style=\"background-color: #e8e8ff\"><td colspan=\"3\" style=\"text-align: right\">";
    echo "<small><a href=\"resource.php?lang=".urlencode($lang)."&resfile=".urlencode($resfile)."&type=".urlencode($type)."&id=".urlencode($id)."\">";
    echo "&lt;&lt; Hide compare with ".get_lang_name($MASTER_LANGUAGE)."</a></small>";
    echo "</td></tr>";

    echo "<tr style=\"background-color: #e8e8ff\"><td>id</td><td>".get_lang_name($lang)."</td><td>".get_lang_name($MASTER_LANGUAGE)."</td></tr>";
}

for ($i=0; $i<16; $i++) {
    $extra = "";

    $uni_str = $res->getString($i);
    if ($compare)
    {
        $master_uni_str = $master_res->getString($i);
        if ((!$master_uni_str && $uni_str) || ($master_uni_str && !$uni_str))
            $extra = " style=\"background-color: #ffb8d0\"";
    }
    
    echo "<tr$extra><td valign=\"top\">".(($id-1)*16+$i)."</td>";
    echo "<td>";

    dump_unicode_or_empty($uni_str);

    if ($compare)
    {
        echo "</td><td>";
        dump_unicode_or_empty($master_uni_str);
    }
    echo "</td></tr>\n";
}
?>
</table>
</body>
</html>