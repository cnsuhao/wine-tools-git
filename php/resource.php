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
    <link rel="stylesheet" href="style.css" type="text/css"/>
    <title><?php echo get_resource_name($type, $id) ?> from <?php echo $resfile?> - Wine translation</title>
</head>
<body>
<?php dump_menu_root() ?> &gt <?php dump_menu_lang($lang) ?> &gt <?php dump_menu_resfile($lang, $resfile) ?> &gt
<?php dump_menu_resource($lang, $resfile, $type, $id) ?>
<h1>Dump of <?php echo get_resource_name($type, $id) ?></h1>

<?php

//include_once("stopwatch.php");

function load_resource(&$resources, $type, $id, $langid, &$res)
{
    $file_type = $type & 0xff;  /* wrc adds 0x100 for *EX resource*/
    $resdata = $resources->loadResource($file_type, $id, get_lang_binid($langid), is_lang_ignore_sublang($langid));
    if (!$resdata)
        die("Resource not found in *.res file\n");
    switch ($type)
    {
        case 4:   /* RT_MENU */
            $res = new MenuResource($resdata[0], $resdata[1]);
            return TRUE;
        case 5:   /* RT_DIALOG */
        case 261: /* res_dialogex */
            $res = new DialogResource($resdata[0], $resdata[1]);
            return TRUE;
        case 6:   /* RT_STRING*/
            $res = new StringTable($resdata[0], $resdata[1], $id);
            return TRUE;
        default:
            die("Unhandled resource type $type");
    }
}

$resources = new ResFile(get_res_path($resfile));

$res_lang = update_lang_from_resfile($lang, $resfile);
load_resource($resources, $type, $id, $res_lang, $res);

$master_res = NULL;
if ($compare)
    load_resource($resources, $type, $id, $MASTER_LANGUAGE, $master_res);

?>

<table style="background-color: #f0f0ff" cellpadding="0" cellspacing="0">
<tr style="background-color: #e0e0ff"><th colspan="5"><?php echo get_resource_name($type, $id) ?></th></tr>
<?php

if (!$compare)
{
    echo "<tr style=\"background-color: #e8e8ff\"><td colspan=\"3\" style=\"text-align: right\">";
    echo "<small>".gen_resource_a($lang, $resfile, $type, $id, TRUE);
    echo "Compare with ".$MASTER_LANGUAGE_NAME." &gt;&gt;</a></small>";
    echo "</td></tr>";
}
else
{
    echo "<tr style=\"background-color: #e8e8ff\"><td colspan=\"5\" style=\"text-align: right\">";
    echo "<small>".gen_resource_a($lang, $resfile, $type, $id, FALSE);
    echo "&lt;&lt; Hide compare with ".get_lang_name($MASTER_LANGUAGE)."</a></small>";
    echo "</td></tr>";

    echo "<tr style=\"background-color: #e8e8ff\"><td>id</td><td>&nbsp;</td><td>".get_lang_name($lang)."</td><td>&nbsp;</td><td>".get_lang_name($MASTER_LANGUAGE)."</td></tr>";
}

$res->dump($master_res);

?>
</table>
</body>
</html>
