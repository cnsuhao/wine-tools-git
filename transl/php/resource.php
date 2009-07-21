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
<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 4.01 Transitional//EN">
<html>
<head>
    <link rel="stylesheet" href="style.css" type="text/css">
    <meta http-equiv="Content-Type" content="text/html; charset=utf-8">
    <title><?php echo get_resource_name($type, $id) ?> from <?php echo $resfile?> - Wine translation</title>
</head>
<body>
<?php dump_menu_root() ?> &gt <?php dump_menu_lang($lang) ?> &gt <?php dump_menu_resfile($lang, $resfile) ?> &gt
<?php dump_menu_resource($lang, $resfile, $type, $id) ?>
<div class="main">
<h1>Dump of <?php echo get_resource_name($type, $id) ?></h1>

<?php

function load_resource(&$resources, $type, $id, $langid, &$res)
{
    $file_type = $type & 0xff;  /* wrc adds 0x100 for *EX resource*/
    $resdata = $resources->loadResource($file_type, $id, get_lang_binid($langid));
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
        case 11:  /* RT_MESSAGETABLE */
            $res = new MessageTable($resdata[0], $resdata[1], $id);
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

<table class="resource" cellpadding="0" cellspacing="0">
<tr class="header"><th colspan="5"><?php echo get_resource_name($type, $id) ?></th></tr>
<?php

if (!$compare)
{
    if ($lang != $MASTER_LANGUAGE)
    {
        echo "<tr class=\"subheader\"><td colspan=\"3\" style=\"text-align: right\">";
        echo "<small>".gen_resource_a($lang, $resfile, $type, $id, TRUE);
        echo "Compare with ".$MASTER_LANGUAGE_NAME." &gt;&gt;</a></small>";
        echo "</td></tr>";
    }
}
else
{
    echo "<tr class=\"subheader\"><td colspan=\"5\" style=\"text-align: right\">";
    echo "<small>".gen_resource_a($lang, $resfile, $type, $id, FALSE);
    echo "&lt;&lt; Hide compare with ".$MASTER_LANGUAGE_NAME."</a></small>";
    echo "</td></tr>";

    echo "<tr class=\"subheader\"><td>id</td><td>&nbsp;</td><td>".get_lang_name($lang)."</td><td>&nbsp;</td><td>".get_lang_name($MASTER_LANGUAGE)."</td></tr>";
}

$res->dump($master_res);

?>
</table>
</div>
</body>
</html>
