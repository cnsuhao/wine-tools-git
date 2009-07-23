<?php

$MASTER_LANGUAGE = "009:01";

$WINE_WIKI_TRANSLATIONS = "<a href=\"redirect.php?url=http://wiki.winehq.org/Translating\">http://wiki.winehq.org/Translating</a>";

static $LOCALE_NAMES = array();

// These resources are retrieved as a sequence of words that need to be converted to a string
function convert_to_unicode($words)
{
    $unistr= '';

    foreach ($words as $word)
        $unistr .= html_entity_decode('&#'.$word.';',ENT_NOQUOTES,'UTF-8');

    return $unistr;
}

function res_enum($header, $f)
{
    global $LOCALE_NAMES;

    // We are only interested in a STRINGTABLE
    if ($header["type"] != 6)
        return FALSE;

    // Look for LOCALE_SLANGUAGE or LOCALE_SENGLANGUAGE
    if ($header["name"] != 1 && $header["name"] != 257)
        return FALSE;

    $data = fread($f, $header["resSize"]);
    $str = new StringTable($header, $data, 0);
    $langid = sprintf("%03x:%02x", $header["language"] & 0x3ff, $header["language"] >> 10);

    if ($header["name"] == 1)
    {
        $LOCALE_NAMES[$langid] = convert_to_unicode($str->getString(2));
    }
    else if ($header["name"] == 257)
    {
        $baseid = get_lang_base($langid);
        $LOCALE_NAMES[$baseid] = convert_to_unicode($str->getString(1))." (Neutral)";
    }
}

function enum_locale_names()
{
    include_once "lib_res.php";
    global $LOCALE_NAMES;

    if (!empty($LOCALE_NAMES))
    {
        return;
    }
    $res = new ResFile("dumps/res/dlls-kernel32.res");
    $res->enumResources("res_enum");
    ksort($LOCALE_NAMES);
}

function validate_lang($id)
{
    global $LOCALE_NAMES;
    enum_locale_names();

    if (!isset($LOCALE_NAMES[$id]))
        die("Invalid lang parameter");

    $lang = preg_replace("/[^0-9a-f:]/", "-", $id);
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
        die("Invalid resource id");
    return $id;
}

function get_lang_name($id)
{
    return get_locale_name($id);
}

function get_lang_base($id)
{
    return preg_replace("/:[0-9a-f]{2}/", ":00", $id);
}

function get_sublangs($id)
{
    if (preg_match("/:00/", $id))
    {
        global $LOCALE_NAMES;
        enum_locale_names();

        $base = preg_replace("/:00/", "", $id);
        $sublangs = array();
        foreach ($LOCALE_NAMES as $key => $value)
            if (preg_match("/$base/", $key) && ($key != $id))
                $sublangs[] = $key;
        return $sublangs;
    }
    else
        return NULL;
}

function show_sublangs($id)
{
    echo "<p class=\"note\"><b>Note:</b> This is the '".get_lang_name($id)."' locale which ".
         "is not used directly but has resources inherited by sublanguages.<br />".
         "You can still use this locale in translations but the results will show up at the ".
         "sublanguages (see below).</p>";

    echo "<div class=\"group\">";
    echo "<h2>Sublanguages</h2>";
    echo "<table>\n";
    echo "<tr><th>Sublanguage</th></tr>\n";
    $sublangs = get_sublangs($id);
    foreach ($sublangs as $key)
    {
        echo "<tr><td>".gen_lang_a($key).get_lang_name($key)."</a></td></tr>";
    }
    echo "</table>\n";
    echo "</div>";
}

function get_lang_binid($lang)
{
    if (!preg_match("/([0-9a-f]{3}):([0-9a-f]{2})/", $lang, $m))
        die("Couldn't pare language code");
    return hexdec($m[1]) + (hexdec($m[2]) << 10);
}

function get_locale_name($localeid)
{
    global $LOCALE_NAMES;
    enum_locale_names();
    return htmlspecialchars($LOCALE_NAMES[$localeid],ENT_QUOTES,'UTF-8');
}

function get_res_path($resfile)
{
    global $DATAROOT;

    $resfile = preg_replace("/\\.rc(#.*)?$/", "", $resfile);
    return "$DATAROOT/dumps/res/".preg_replace("/[^a-zA-Z0-9]/", "-", $resfile).".res";
}

function get_resfile_name($resfile)
{
    if (preg_match("*^([a-zA-Z0-9/.-_]+)#locale([0-9a-f]{3}:[0-9a-f]{2})$*", $resfile, $m))
    {
        return "Locale data for: ".get_locale_name($m[2])." (".$m[1].")";
    }
    return $resfile;
}

function get_resource_name($type, $name)
{
    $types = array();
    $types[1] = "CURSOR";
    $types[2] = "BITMAP";
    $types[3] = "ICON";
    $types[4] = "MENU";
    $types[5] = "DIALOG";
    $types[6] = "STRINGTABLE";
    $types[7] = "FONTDIR";
    $types[8] = "FONT";
    $types[9] = "ACCELERATOR";
    $types[10] = "RCDATA";
    $types[11] = "MESSAGE";
    $types[12] = "GROUP_CURSOR";
    $types[14] = "GROUP_ICON";
    $types[16] = "VERSION";
    $types[260] = "MENUEX";
    $types[261] = "DIALOGEX";
    $types[262] = "USER";

    if (is_numeric($name))
        $pname = "#".$name;
    else
        $pname = $name;

    if (isset($types[$type]))
        $ret = $types[$type]." ".$pname;
    else
        $ret = $types[$type]." ".$pname;

    if ($type == 6)
        $ret .= " (strings ".($name*16 - 16)."..".($name*16 - 1).")";
    return $ret;    
}

function is_dumpable_type($type)
{
    return ($type == 4) || ($type == 5) || ($type == 6) || ($type == 11) || ($type == 261 /* wrc for DIALOGEX */);
}

function update_lang_from_resfile($lang, $resfile)
{
    if (preg_match("/#locale([0-9a-f]{3}:[0-9a-f]{2})?$/", $resfile, $m))
        return $m[1];
    return $lang;
}

function gen_lang_a($lang)
{
    return "<a href=\"lang.php?lang=".urlencode($lang)."\">";
}

function gen_resfile_a($lang, $resfile)
{
    return "<a href=\"resfile.php?lang=".urlencode($lang)."&resfile=".urlencode($resfile)."\">";
}

function gen_resource_a($lang, $resfile, $type, $id, $compare=FALSE)
{
    if ($compare)
        $extra = "&compare=";
    else
        $extra = "";
    return "<a href=\"resource.php?lang=".urlencode($lang)."&resfile=".urlencode($resfile)."&type=".urlencode($type)."&id=".urlencode($id)."$extra\">";
}

function dump_menu_root()
{
    echo "<a href=\"index.php\">Wine translations</a>";
}

function dump_menu_lang($lang, $link = TRUE)
{
    if ($link)
        echo gen_lang_a($lang);
    echo get_lang_name($lang);
    if ($link)
        echo "</a>";
}

function dump_menu_resfile($lang, $resfile, $link = TRUE)
{
    if ($link)
        echo gen_resfile_a($lang, $resfile);
    echo get_resfile_name($resfile);
    if ($link)
        echo "</a>";
}

function dump_menu_resource($lang, $resfile, $type, $id)
{
    echo get_resource_name($type, $id);
}

?>
