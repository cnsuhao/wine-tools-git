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

function validate_type($type)
{
    if (!preg_match("/^[0-9]+$/", $type))
        die("Invalid type");
    return $type;
}

function validate_resfile($resfile)
{
    if (!preg_match("*^[a-zA-Z0-9/.-_]+$*", $resfile))
        die("Invalid resource file");
    return $resfile;
}

function validate_id($id)
{
    if (!preg_match("/^[a-zA-Z0-9_]+$/", $id))
        die("Invalid resource file");
    return $id;
}

function get_lang_name($id)
{
    global $DATAROOT;

    return file_get_contents("$DATAROOT/conf/$id");
}

?>
