<?php

$MASTER_LANGUAGE = "009:01";

function validate_lang($id)
{
    global $DATAROOT;
    
    $lang = preg_replace("/[^0-9a-f:]/", "-", $_REQUEST['lang']);
    if (!file_exists("$DATAROOT/conf/$lang") || !file_exists("$DATAROOT/langs/$lang"))
        die("Invalid lang parameter");
    return $lang;
}

function get_lang_name($id)
{
    global $DATAROOT;

    return file_get_contents("$DATAROOT/conf/$id");
}

?>
