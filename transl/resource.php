<?php
include("config.php");
include("lib.php");
include("lib_res.php");

$lang = validate_lang($_REQUEST['lang']);
$resfile = validate_resfile($_REQUEST['resfile']);
$type = validate_type($_REQUEST['type']);
$id = validate_id($_REQUEST['id']);
$compare = isset($_REQUEST['compare']);
$pedantic = isset($_REQUEST['pedantic']);

?>
<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 4.01 Transitional//EN">
<html>
<head>
    <link rel="stylesheet" href="style.css" type="text/css">
    <meta http-equiv="Content-Type" content="text/html; charset=utf-8">
    <title><?php echo get_resource_name($type, $id) ?> from <?php echo $resfile?> - Wine translation</title>
</head>
<body>
<div class="navbar">
<?php dump_menu_resource($lang, $resfile, $type, $id); ?>
</div>
<div class="main">
<h1>Dump of <?php echo get_resource_name($type, $id) ?></h1>

<table class="resource" cellpadding="0" cellspacing="0">
<tr class="header"><th colspan="5"><?php echo get_resource_name($type, $id) ?></th></tr>

<?php

$resources = new ResFile(get_res_path($resfile));
load_resource($resources, $type, $id, $lang, $res);

$master_res = NULL;
if ($compare)
    load_resource($resources, $type, $id, $MASTER_LANGUAGE, $master_res);

$warnings = 0;
if ($pedantic && ($lang != "$MASTER_LANGUAGE"))
{
    if (!$master_res)
        load_resource($resources, $type, $id, $MASTER_LANGUAGE, $master_res);
    $counts = $res->getcounts($master_res);
    $warnings = $counts['warnings'];
}

if ($compare || ($pedantic && $warnings != 0))
{
    if ($compare)
    {
        echo "<tr class=\"subheader\"><td colspan=\"5\" style=\"text-align: right\">";
        echo "<small>".gen_resource_a($lang, $resfile, $type, $id, FALSE);
        echo "&lt;&lt; Hide compare with ".get_locale_name($MASTER_LANGUAGE)."</a></small>";
        echo "</td></tr>\n";
    }

    echo "<tr class=\"subheader\"><td>id</td><td>&nbsp;</td><td>".get_lang_name($lang).
         "</td><td>&nbsp;</td><td>".get_lang_name($MASTER_LANGUAGE)."</td></tr>\n";

    $res->dump($master_res);
}
else
{
    if ($lang != $MASTER_LANGUAGE)
    {
        echo "<tr class=\"subheader\"><td colspan=\"3\" style=\"text-align: right\">";
        echo "<small>".gen_resource_a($lang, $resfile, $type, $id, TRUE);
        echo "Compare with ".get_locale_name($MASTER_LANGUAGE)." &gt;&gt;</a></small>";
        echo "</td></tr>\n";
    }

    $res->dump(NULL);
}

?>

</table>
</div>
</body>
</html>
