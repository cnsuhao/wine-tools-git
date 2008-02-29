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
<?php dump_menu_root() ?> &gt <?php dump_menu_lang($lang) ?> &gt <?php dump_menu_resfile($lang, $resfile) ?> &gt
<?php dump_menu_resource($lang, $resfile, $type, $id) ?>
<h1>Resource <?php echo "$id ($type)"?></h1>

<?php

$resources = new ResFile(get_res_path($resfile));

$res_lang = update_lang_from_resfile($lang, $resfile);
$resdata = $resources->loadResource($type, $id, get_lang_binid($res_lang), is_lang_ignore_sublang($lang));
if (!$resdata)
    die("Resource not found in *.res file\n");
$res = new StringTable($resdata[0], $resdata[1], $id);

$master_res = NULL;
if ($compare)
{
    $resdata = $resources->loadResource($type, $id, $MASTER_LANGUAGE_BINID);
    if (!$resdata)
        echo ("<b>Can't compare with master language as resource not found</b>\n");
    else
        $master_res = new StringTable($resdata[0], $resdata[1], $id);
}
unset($resdata);

?>

<table style="background-color: #f0f0ff">
<tr style="background-color: #e0e0ff"><th colspan="3">String table #<?php echo $id?></th></tr>
<?php

if (!$compare)
{
    echo "<tr style=\"background-color: #e8e8ff\"><td colspan=\"2\" style=\"text-align: right\">";
    echo "<small>".gen_resource_a($lang, $resfile, $type, $id, TRUE);
    echo "Compare with ".$MASTER_LANGUAGE_NAME." &gt;&gt;</a></small>";
    echo "</td></tr>";
}
else
{
    echo "<tr style=\"background-color: #e8e8ff\"><td colspan=\"3\" style=\"text-align: right\">";
    echo "<small>".gen_resource_a($lang, $resfile, $type, $id, FALSE);
    echo "&lt;&lt; Hide compare with ".get_lang_name($MASTER_LANGUAGE)."</a></small>";
    echo "</td></tr>";

    echo "<tr style=\"background-color: #e8e8ff\"><td>id</td><td>".get_lang_name($lang)."</td><td>".get_lang_name($MASTER_LANGUAGE)."</td></tr>";
}

$res->dump($master_res);

?>
</table>
</body>
</html>
