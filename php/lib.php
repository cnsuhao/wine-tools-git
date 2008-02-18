<?php

$MASTER_LANGUAGE = "009:01";
$MASTER_LANGUAGE_BINID = 1033;
$MASTER_LANGUAGE_NAME = "English (US)";

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

function is_lang_ignore_sublang($lang)
{
    if (!preg_match("/([0-9a-f]{3}):00/", $lang, $m))
        return FALSE;
    return (get_lang_name($m[1].":01") == "collapse");
}

function get_lang_binid($lang)
{
    if (!preg_match("/([0-9a-f]{3}):([0-9a-f]{2})/", $lang, $m))
        die("Couldn't pare language code");
    return hexdec($m[1]) + (hexdec($m[2]) << 10);
}

function get_res_path($respath)
{
    global $DATAROOT;

    $respath = preg_replace("/\\.rc$/", "", $respath);
    return "$DATAROOT/dumps/res/".preg_replace("/[^a-zA-Z0-9]/", "-", $respath).".res";
}

?>
