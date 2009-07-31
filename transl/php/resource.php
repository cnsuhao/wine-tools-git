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
        echo "Compare with ".get_locale_name($MASTER_LANGUAGE)." &gt;&gt;</a></small>";
        echo "</td></tr>";
    }
}
else
{
    echo "<tr class=\"subheader\"><td colspan=\"5\" style=\"text-align: right\">";
    echo "<small>".gen_resource_a($lang, $resfile, $type, $id, FALSE);
    echo "&lt;&lt; Hide compare with ".get_locale_name($MASTER_LANGUAGE)."</a></small>";
    echo "</td></tr>";

    echo "<tr class=\"subheader\"><td>id</td><td>&nbsp;</td><td>".get_lang_name($lang)."</td><td>&nbsp;</td><td>".get_lang_name($MASTER_LANGUAGE)."</td></tr>";
}

$res->dump($master_res);

?>
</table>
</div>
</body>
</html>
