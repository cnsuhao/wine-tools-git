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
    if (!preg_match("*^[a-zA-Z0-9/.-_]+(#locale[0-9a-f]{3}:[0-9a-f]{2})?$*", $resfile))
        die("Invalid resource file");
    return $resfile;
}

function validate_id($id)
{
    if (!preg_match("/^[a-zA-Z0-9_]+$/", $id))
        die("Invalid resource file");
    return $id;
}

function get_raw_lang_name($id)
{
    static $lang_cache = array();
    if (empty($lang_cache[$id]))
    {
        global $DATAROOT;

        $name = file_get_contents("$DATAROOT/conf/$id");
        $lang_cache[$id] = $name;
    }
    return $lang_cache[$id];
}

function get_lang_name($id)
{
    return preg_replace("/\[ignore-sublang\]/", "", get_raw_lang_name($id));
}

function has_lang_flag($id, $flag)
{
    return is_int(strpos(get_raw_lang_name($id), "[".$flag."]"));
}

function is_lang_ignore_sublang($lang)
{
    return has_lang_flag($lang, "ignore-sublang");
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

    $respath = preg_replace("/\\.rc(#.*)?$/", "", $respath);
    return "$DATAROOT/dumps/res/".preg_replace("/[^a-zA-Z0-9]/", "-", $respath).".res";
}

function update_lang_from_resfile($lang, $resfile)
{
    if (preg_match("/#locale([0-9a-f]{3}:[0-9a-f]{2})?$/", $resfile, $m))
        return $m[1];
    return $lang;
}

?>
