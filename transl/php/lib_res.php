<?php

$CONSTS["RT_MENU"] = 4;
$CONSTS["RT_STRING"] = 6;

$CONSTS["MF_CHECKED"]   = 0x0008;
$CONSTS["MF_POPUP"]     = 0x0010;
$CONSTS["MF_END"]       = 0x0080;
$CONSTS["MF_SEPARATOR"] = 0x0800;

$CONSTS["MFT_DISABLED"] =   0x3;

$CONSTS["DS_SETFONT"] = 0x0040;

$CONSTS["BS_MULTILINE"] = 0x2000;

function get_byte(&$data)
{
    if (strlen($data)  < 1)
        die("not enough data");
    $cx = unpack("Cc", $data);
    $data = substr($data, 1);
    return $cx["c"];
}

function get_word(&$data)
{
    if (strlen($data)  < 2)
        die("not enough data");
    $cx = unpack("vc", $data);
    $data = substr($data, 2);
    return $cx["c"];
}

function get_dword(&$data)
{
    if (strlen($data)  < 4)
        die("not enough data");
    $cx = unpack("Vc", $data);
    $data = substr($data, 4);
    return $cx["c"];
}

function get_stringorid_asascii($data, &$pos)
{
    $len = strlen($data);

    if ((ord($data[$pos]) == 0xff) && (ord($data[$pos + 1]) == 0xff))
    {
        if ($len < 4)
            die("not enough data");
        $pos += 4;
        return (ord($data[$pos - 2]) + (ord($data[$pos - 1]) << 8));
    }

    $ret ="";
    for ($i = $pos; (ord($data[$i]) != 0) || (ord($data[$i+1]) != 0); $i += 2)
    {
        if (ord($data[$i+1]))
            $ret .= '?';
        else
            $ret .= (ord($data[$i])>=0x80 ? '?' : $data[$i]);
    }

    $pos = $i + 2;

    if ($pos >= $len)
        die("not enough data");

    return $ret;
}

/* same as get_stringorid, but uses 0xff00 as the marker of an oridinal */
function get_stringorid($data, &$pos, $magic = 0xffff)
{
    $len = strlen($data);

    if ((ord($data[$pos]) == $magic >> 8) && (ord($data[$pos + 1]) == ($magic & 0xff)))
    {
        if ($len < 4)
            die("not enough data");
        $pos += 4;
        return (ord($data[$pos - 2]) + (ord($data[$pos - 1]) << 8));
    }

    $ret = array();
    for ($i = $pos; (ord($data[$i]) != 0) || (ord($data[$i+1]) != 0); $i += 2)
    {
        $ret[] = (ord($data[$i]) + (ord($data[$i + 1]) << 8));
    }

    $pos = $i + 2;

    if ($pos >= $len)
        die("not enough data");

    return $ret;
}

/* load NUL-terminated string */
function get_string_nul(&$data)
{
    $str = array();
    while (TRUE)
    {
        $w = get_word($data);
        if ($w == 0)
            break;
        $str[] = $w;
    }
    return $str;
}

function dump_unicode($unistr, $quoted = TRUE)
{
    if ($quoted)
        echo "&quot;";
    for ($i = 0; $i < count($unistr); $i++)
    {
        if (($unistr[$i] >= ord('a') && $unistr[$i] <= ord('z'))
                || ($unistr[$i] >= ord('A') && $unistr[$i] <= ord('Z'))
                || ($unistr[$i] >= ord('0') && $unistr[$i] <= ord('9'))
                || $unistr[$i] == ord(' '))
            echo chr($unistr[$i]);
        else if ($unistr[$i] == 10) { 
            echo "<span class=\"resmeta\">\\n</span>";
            if ($i < count($unistr) - 1)
                echo "<br/>\n";
        } else if ($unistr[$i] == 9) { 
            echo "<span class=\"resmeta\">\\t</span>";
        } else if ($unistr[$i] == 0) {
            echo "<span class=\"resmeta\">\\0</span>";
        } else
            echo "&#x".dechex($unistr[$i]).";";
    }
    if ($quoted)
        echo "&quot;";
}

function dump_unicode_or_empty($uni_str)
{
    if ($uni_str)
        dump_unicode($uni_str);
    else
        echo "<span class=\"resmeta\">empty</span>";
}

function dump_unicode_or_id($unistr_or_int)
{
    if (is_int($unistr_or_int))
        echo "<span class=\"resmeta\">".$unistr_or_int."</span>";
    else
        dump_unicode($unistr_or_int);
}

function is_equal_unicode_or_id($unistr_or_int1, $unistr_or_int2)
{
    if (is_int($unistr_or_int1))
        return is_int($unistr_or_int2) && $unistr_or_int1 == $unistr_or_int2;
        
    if (is_int($unistr_or_int2))
        return FALSE;

    /* both arrays of UTF-16 */
    if (count($unistr_or_int1) != count($unistr_or_int2))
        return FALSE;
    for ($i = 0; $i < count($unistr_or_int1); $i++)
        if ($unistr_or_int1[$i] != $unistr_or_int2[$i])
            return FALSE;
    return TRUE;
}

function dump_resource_row($id, &$resource, &$master, $method_name, $diff_method_name, $lparam, $master_lparam = NULL)
{
    $extra = "";
    if ($master && $diff_method_name)
        if ($master_lparam == NULL)
        {
            if ($resource->$diff_method_name($master, $lparam, TRUE))
                $extra = " class=\"diff\"";
        }
        else
        {
            if ($resource->$diff_method_name($master, $lparam, $master_lparam, TRUE))
                $extra = " class=\"diff\"";
        }

    if ($master_lparam == NULL)
        $master_lparam = $lparam;
    echo "<tr$extra><td>$id</td><td></td>\n<td>";
    call_user_func(array($resource, $method_name), $lparam);
    if ($master)
    {
        echo "</td><td></td>\n<td>";
        call_user_func(array($master, $method_name), $master_lparam);
    }
    echo "</td></tr>\n\n";
}

/* Longest common subsequence - simple O(n^2) time and O(n^2) space algorithm,
 * but resources are small so this should be OK */
function diff_sequences(&$res1, $count1, &$res2, $count2, $compare_method)
{
    $mincount = min($count1, $count2);
    for ($start = 0; $start < $mincount; $start++)
        if (!$res1->$compare_method($res2, $start, $start))
            break;

    if (($start == $mincount) && $count1 == $count2)
        return array_fill(0, $mincount, 3);

    for ($end = 0; $end < $mincount - $start; $end++)
        if (!$res1->$compare_method($res2, $count1 - 1 - $end, $count2 - 1 - $end))
            break;

    $out = array();
    $tabdyn = array_fill(0, $count1 - $start - $end + 1,
                array_fill(0, $count2 - $start - $end + 1, 0));

    for ($i = 1; $i <= $count1 - $start - $end; $i++)
    {
        for ($j = 1; $j <= $count2 - $start - $end; $j++)
        {
            if ($res1->$compare_method($res2, $start + $i - 1, $start + $j - 1))
                $tabdyn[$i][$j] = $tabdyn[$i-1][$j-1] + 1;
            else if ($tabdyn[$i][$j-1] > $tabdyn[$i-1][$j])
                $tabdyn[$i][$j] = $tabdyn[$i][$j-1];
            else
                $tabdyn[$i][$j] = $tabdyn[$i-1][$j];
        }
    }

    /* backtrack (produces results in reverse order) */
    $out = ($end > 0 ? array_fill(0, $end, 3) : array());
    $i = $count1 - $start - $end;
    $j = $count2 - $start - $end;
    while ($i > 0 || $j > 0) {
        if ($i == 0)
            $step = 2;
        else if ($j == 0)
            $step = 1;
        else
        {
            if ($res1->$compare_method($res2, $start + $i - 1, $start + $j - 1))
                $step = 3;
            else if ($tabdyn[$i][$j-1] > $tabdyn[$i-1][$j])
                $step = 2;
            else
                $step = 1;
        }

        $out[] = $step;

        if ($step & 1)
            $i--;
        if ($step & 2)
            $j--;
    }
    if ($start > 0)
        $out += array_fill(count($out), $start, 3);
    return array_reverse($out);
}

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

class ResFile
{
    var $file;

    function ResFile($path)
    {
        $this->file = fopen("$path", "rb");
        if ($this->file == NULL)
            die("Couldn't open resource file");
    }
    
    function enumResources($callback, $lparam = 0)
    {
        fseek($this->file, 0);
        $pos = 0;

        do {
            $data = fread($this->file, 8);

            $len = strlen($data);
            if ($len == 0)
                break;
            if ($len < 8)
                die("Couldn't read header");

            $header = unpack("VresSize/VheaderSize", $data);
            assert($header["headerSize"] > 8);

            $len = $header["headerSize"] - 8;
            $data = fread($this->file, $len);
            if (strlen($data) < $len)
                die("Couldn't read header");

            $strpos = 0;
            $header["type"] = get_stringorid_asascii($data, $strpos);
            $header["name"] = get_stringorid_asascii($data, $strpos);
            if ($strpos & 3)  /* DWORD padding */
                $strpos += 2;
            $data = substr($data, $strpos);
            $header += unpack("VdataVersion/vmemoryOptions/vlanguage/Vversion/Vcharacteristics", $data);
        
            $pos += ($header["headerSize"] + $header["resSize"] + 3) & 0xfffffffc;

            if (call_user_func($callback, $header, $this->file, $lparam))
                return TRUE;

            fseek($this->file, $pos);
        } while (true);
        return FALSE;
    }

    function loadResource($type, $name, $language)
    {
        fseek($this->file, 0);
        $pos = 0;

        do {
            $data = fread($this->file, 512);

            $len = strlen($data);
            if ($len == 0)
                break;
            if ($len < 8)
                die("Couldn't read header");

            $header = unpack("Va/Vb", $data);
            $resSize = $header["a"];
            $headerSize = $header["b"];
            assert($headerSize > 8 && $headerSize <= $len);

            $strpos = 8;
            $res_type = get_stringorid_asascii($data, $strpos);
            if ($res_type == $type)
            {
                $res_name = get_stringorid_asascii($data, $strpos);
                if ($res_name == strtoupper($name))
                {
                    if ($strpos & 3)  /* DWORD padding */
                        $strpos += 2;
                    $data = substr($data, $strpos);
                    $header = unpack("VdataVersion/vmemoryOptions/vlanguage/Vversion/Vcharacteristics", $data);

                    $curr_lang = $header["language"];
                    if ($curr_lang == $language)
                    {
                        fseek($this->file, $pos + $headerSize);
                        $out = fread($this->file, $resSize);
                        return array($header, $out);
                    }
                }
            }
            
            $pos += ($headerSize + $resSize + 3) & 0xfffffffc;
            
            fseek($this->file, $pos);
        } while (true);
        
        return FALSE;
    }
}

function dump_header($header)
{
    var_dump($header);
    echo "<br/>";
    return FALSE;
}

class Resource
{
    var $header;

    function Resource($header)
    {
        $this->header = $header;
    }
}

class StringTable extends Resource
{
    var $strings;
    var $table_id;

    function StringTable($header, $data, $table_id)
    {
        $this->Resource($header);
        $this->strings = array();
        $this->table_id = $table_id;
        for ($i = 0; $i < 16; $i++)
        {
            $len = get_word($data);
//            echo "<br/>len=$len";
            $str = array();
            for ($j = 0; $j < $len; $j ++)
                $str[] = get_word($data);
            $this->strings[] = $str;
        }
        if (strlen($data) > 0)
            die("unexpected data in STRINGTABLE resource\n");
    }
    
    function getString($id)
    {
        return $this->strings[$id];
    }
    
    function dump_string($lparam)
    {
        dump_unicode_or_empty($this->strings[$lparam]);
    }

    function is_string_different(&$other, $lparam, $pedantic = TRUE)
    {
        $uni_str = $this->strings[$lparam];
        $other_uni_str = $other->strings[$lparam];

        $generic = (!$other_uni_str && $uni_str) || ($other_uni_str && !$uni_str);

        if ($pedantic != TRUE)
            return $generic;

        return $generic ||
               (($uni_str && $other_uni_str) && ($uni_str == $other_uni_str));
    }

    function dump($master_res = NULL)
    {
        for ($i=0; $i<16; $i++)
            dump_resource_row(($this->table_id-1)*16+$i, $this, $master_res,
                "dump_string", "is_string_different", $i);
    }    
}

class MessageTable extends Resource
{
    var $strings;
    var $table_id;
    var $message_count;

    function MessageTable($header, $data, $table_id)
    {
        $this->Resource($header);
        $this->strings = array();
        $this->table_id = $table_id;
        $this->message_count = 0;

        // First skip some header information (basically ignore)
        $dummy = get_dword($data);
        $dummy = get_dword($data);
        $dummy = get_dword($data);
        // Where can we find the first message string
        $offset = get_dword($data);
        // This block shows where there are gaps between message id's (with offsets to the next one)
        for ($i = 0; $i < ($offset - 16) / 4; $i++)
            $dummy = get_dword($data);

        for ($i = 0; strlen($data) > 0; $i++)
        {
            $counter = 0;
            $str = array();

            // Were can we find the next message string
            $offset = get_word($data);
            $counter += 2;

            // Ansi = 0; Unicode = 1 ?
            $unicode = get_word($data);
            $counter += 2;

            while ($char = get_word($data))
            {
                $counter += 2;
                $str[] = $char;
            }
            $counter += 2;
            $this->strings[] = $str;
            $this->message_count++;
            for ($j = 0; $j < ($offset - $counter) / 2; $j++)
                $dummy = get_word($data);
        }
    }
    
    function getString($id)
    {
        return $this->strings[$id];
    }
    
    function dump_string($lparam)
    {
        dump_unicode_or_empty($this->strings[$lparam]);
    }

    function is_string_different(&$other, $lparam, $pedantic = TRUE)
    {
        $uni_str = $this->strings[$lparam];
        $other_uni_str = $other->strings[$lparam];

        $generic = (!$other_uni_str && $uni_str) || ($other_uni_str && !$uni_str);

        if ($pedantic != TRUE)
            return $generic;

        return $generic ||
               (($uni_str && $other_uni_str) && ($uni_str == $other_uni_str));
    }

    function dump($master_res = NULL)
    {
        for ($i=0; $i<$this->message_count; $i++)
            dump_resource_row(($this->table_id-1)*16+$i, $this, $master_res,
                "dump_string", "is_string_different", $i);
    }    
}

class MenuResource extends Resource
{
    var $items;

    function parse_menu(&$data, $level)
    {
        global $CONSTS;
        do
        {
            $item = array();
            $item["state"] = get_word($data);
            if (!($item["state"] & $CONSTS["MF_POPUP"]))
                $item["id"] = get_word($data);
            else
                $item["id"] = 0;
            $item["text"] = get_string_nul($data);

/*            echo "lvl=$level ";
            dump_unicode($item["text"]);
            echo "word=".$item["state"]."<br/>";*/


            $item["resinfo"] = 0;
            if ($item["state"] & $CONSTS["MF_POPUP"])
                $item["resinfo"] |= 1;
            if ($item["state"] & $CONSTS["MF_END"])
                $item["resinfo"] |= $CONSTS["MF_END"];

            $item["state"] &= 0xff6f;   /* clear MF_POPUP|MF_END */
            $item["level"] = $level;

            $this->items[] = $item;
            if ($item["resinfo"] & 1)
                $this->parse_menu($data, $level + 1);
        }
        while (!($item["resinfo"] & $CONSTS["MF_END"]));
    }

    function MenuResource($header, $data)
    {
        $this->Resource($header);
        $this->items = array();

        $version = get_word($data);
        $header = get_word($data);
        $data = substr($data, $header);

        if ($version == 0)
            $this->parse_menu($data, 0);
        else
            die("Unsupported version $version");

//        echo urlencode($data);
        if (strlen($data) > 0)
            die("unexpected data in MENU resource\n");
    }
    
    function draw_tree_img($name)
    {
        echo "<img src=\"img/tree-$name.png\" align=\"center\" height=\"28\"/>";
    }

    function menuitem_equals(&$res2, $i, $j)
    {
        return (($this->items[$i]["id"] == $res2->items[$j]["id"]) &&
            ($this->items[$i]["level"] == $res2->items[$j]["level"]) &&
            (($this->items[$i]["resinfo"]&1) == ($res2->items[$j]["resinfo"]&1)));
    }

    function handle_indent(&$tstate, $resinfo)
    {
        for ($i = 0; $i < count($tstate) - ($resinfo === NULL ? 0 : 1); $i++)
        {
            if ($tstate[$i])
                $this->draw_tree_img("vert");
            else
                $this->draw_tree_img("empty");
        }

        if ($resinfo === NULL)
            return;

        if ($resinfo & 0x80)
            $this->draw_tree_img("l");
        else
            $this->draw_tree_img("t");

        if (($resinfo & 0x81) == 0x81) { /* END & POPUP*/
            $tstate[count($tstate) - 1] = FALSE;
            $tstate[] = TRUE;
        } else if ($resinfo & 1) { /* POPUP */
            $tstate[] = TRUE;
        } else if ($resinfo & 0x80) {  /* END */
            array_pop($tstate);
            while (count($tstate) > 0 && $tstate[count($tstate) - 1] === FALSE)
                array_pop($tstate);
        }
    }
    
    function dump_title($item)
    {
        global $CONSTS;
        if (($item["state"] & $CONSTS["MF_SEPARATOR"]) || 
            (empty($item["text"]) && !($item["resinfo"] & 0x1)))
        {
            echo " <span class=\"resmeta\">SEPARATOR</span>";
            return;
        }
        
        if ($item["state"] & $CONSTS["MF_CHECKED"])
            echo "<img src=\"img/iconsm-check.png\"/>";

        if ($item["state"] & $CONSTS["MFT_DISABLED"])
            echo "<span class=\"resdisabled\">";
        dump_unicode($item["text"]);
        if ($item["state"] & $CONSTS["MFT_DISABLED"])
            echo "</span>";
    }

    function dump_menuitem($lparam)
    {
        $pos = $lparam[0];
        $do_show = $lparam[1];
        $tstate =& $lparam[2];
        if (!$do_show)
        {
            $this->handle_indent($tstate, NULL);
            return;
        }

        $this->handle_indent($tstate, $this->items[$pos]["resinfo"]);
        $this->dump_title($this->items[$pos]);
    }

    function is_menuitem_different(&$other, $lparam, $other_lparam)
    {
        if (!$lparam[1] || !$other_lparam[1]) /* one of the items is not shown */
            return TRUE;

        $pos = $lparam[0];
        $other_pos = $other_lparam[0];
        return $this->items[$pos]["state"] != $other->items[$other_pos]["state"];
    }

    function dump($master_res = NULL)
    {
        if ($master_res)
        {
            $show = diff_sequences($this, count($this->items),
                                   $master_res, count($master_res->items),
                                   'menuitem_equals');
        }
        else
            $show = array_fill(0, count($this->items), 1);

        $tstate = array(TRUE);
        $tstate_master = array(TRUE);
        $pos = 0;
        $master_pos = 0;
        for ($i=0; $i<count($show); $i++) {
            $id = ($show[$i] & 1 ? $this->items[$pos]["id"] : $master_res->items[$master_pos]["id"]);
            dump_resource_row($id, $this, $master_res,
                "dump_menuitem", "is_menuitem_different",
                array($pos, $show[$i] & 1, &$tstate),
                array($master_pos, $show[$i] & 2, &$tstate_master));

            if ($show[$i] & 1)
                $pos++;
            if ($show[$i] & 2)
                $master_pos++;
        }
    }
}

class DialogResource extends Resource
{
    var $extended;
    var $style;
    var $exStyle;
    var $dwHelpId;
    var $x, $y, $cx, $cy;
    var $menuName;
    var $className;
    var $title;
    var $fontSize;
    var $fontWeight;
    var $fontItalic;
    var $fontCharset;
    var $fontName;
    var $items;

    function DialogResource($header, $data)
    {
        global $CONSTS;
        $orig_size = strlen($data);

        $this->Resource($header);
        $this->items = array();

        $temp = substr($data, 0, 4);
        $signature = get_word($temp);
        $dlgver = get_word($temp);
        $this->extended = ($signature == 1 && $dlgver == 0xffff);
        if ($this->extended)       /* DIALOGEX resource*/
        {
            $dummy = get_dword($data);
            $this->dwHelpId = get_dword($data);
            $this->exStyle = get_dword($data);
            $this->style = get_dword($data);
        } else                     /* DIALOG resource*/
        {
            $this->style = get_dword($data);
            $this->exStyle = get_dword($data);
            $this->dwHelpId = 0;
        }

        $cItems = get_word($data);
        $this->x = get_word($data);
        $this->y = get_word($data);
        $this->cx = get_word($data);
        $this->cy = get_word($data);

        $pos = 0;
        $this->menuName = get_stringorid($data, $pos);
        $this->className = get_stringorid($data, $pos);
        $this->title = get_stringorid($data, $pos, 0xff00);
        $data = substr($data, $pos);

        if ($this->style & $CONSTS["DS_SETFONT"])
        {
            $this->fontSize = get_word($data);
            if ($this->extended)
            {
                $this->fontWeight = get_word($data);
                $this->fontItalic = get_byte($data);
                $this->fontCharset = get_byte($data);
            }
            $this->fontName = get_string_nul($data);
        }

        $this->items = array();
        for ($i = 0; $i < $cItems; $i++)
        {
            $item = array();

            $align = (($orig_size - strlen($data)) & 3);  /* DWORD align */
            if ($align > 0)
                $data = substr($data, 4-$align);

            if ($this->extended)
            {
                $item['dwHelpId'] = get_dword($data);
                $item['exStyle'] = get_dword($data);
                $item['style'] = get_dword($data);
            }
            else
            {
                $item['style'] = get_dword($data);
                $item['exStyle'] = get_dword($data);
                $item['dwHelpId'] = 0;
            }
            $item['x'] = get_word($data);
            $item['y'] = get_word($data);
            $item['cx'] = get_word($data);
            $item['cy'] = get_word($data);
            if ($this->extended)
                $item['id'] = get_dword($data);
            else
                $item['id'] = get_word($data);
            $pos = 0;
            $item['className'] = get_stringorid($data, $pos);
            $item['text'] = get_stringorid($data, $pos);

            $data = substr($data, $pos);
            $cbExtra = get_word($data);
            if ($cbExtra > strlen($data))
                die("Not enough data to skip cbExtra");
            $data = substr($data, $cbExtra);
            $this->items[] = $item;
        }
        if (strlen($data) >= 4)  /* small padding at the end is possible */
            die("unexpected data in DIALOG resource (".strlen($data)." bytes)\n");
    }

    /* check if controls should be in different rows in the dump */    
    function control_equals(&$res2, $i, $res2_i)
    {
        $this_ctrl = $this->items[$i];
        $other_ctrl = $res2->items[$res2_i];
        return ($this_ctrl['id'] == $other_ctrl['id']);
    }

    function dump_header()
    {
        echo "DIALOG".($this->extended?"EX":""). " ".$this->x.", ".$this->y.
            ", ".$this->cx.", ".$this->cy;
        if ($this->extended)
            echo ", ".$this->dwHelpId;
    }

    function dump_hex($lparam)
    {
        $field = $lparam[0];
        $keyword = $lparam[1];
        printf("$keyword 0x%x", $this->$field);
    }

    function is_hex_different(&$other, $lparam)
    {
        $field = $lparam[0];
        return ($this->$field != $other->$field);
    }

    function dump_string($lparam)
    {
        $field = $lparam[0];
        $keyword = $lparam[1];
        echo "$keyword ";
        dump_unicode_or_id($this->$field);
    }

    function is_string_different(&$other, $lparam)
    {
        $field = $lparam[0];
        return !is_equal_unicode_or_id($this->$field, $other->$field);
    }

    function dump_font()
    {
        echo "FONT ".$this->fontSize.", ";
        dump_unicode($this->fontName);
        if ($this->extended)
        {
            echo ", ".$this->fontWeight;
            echo ", ".$this->fontItalic;
        }
    }

    function dump_control($lparam)
    {
        if (!$lparam[1])  /* don't show */
            return;
        $item = $this->items[$lparam[0]];
        echo "&nbsp;&nbsp;&nbsp;&nbsp;CONTROL  ";
        dump_unicode_or_id($item['text']);
        echo ", ".$item['id'].", ";
        dump_unicode_or_id($item['className']);
        printf(", 0x%x, %d, %d, %d, %d, 0x%x", $item['style'], $item['x'],
            $item['y'], $item['cx'], $item['cy'], $item['exStyle']);
        if ($this->extended && $item['dwHelpId'])
        {
            echo ", ".$item['dwHelpId'];
        }
    }

    /* check if the row should be in red */
    function is_control_different(&$other, $lparam, $other_lparam, $pedantic = TRUE)
    {
        global $CONSTS;
        if (!$lparam[1] || !$other_lparam[1]) /* one item is missing */
            return TRUE;

        $this_ctrl = $this->items[$lparam[0]];
        $other_ctrl = $other->items[$other_lparam[0]];

        $ignore_style = 0;
        if (is_int($this_ctrl['className']) && $this_ctrl['className'] == 0x80 /* button */)
            $ignore_style = $CONSTS["BS_MULTILINE"];

        $generic = ($this_ctrl['id'] != $other_ctrl['id']) ||
                   (($this_ctrl['style'] | $ignore_style) != ($other_ctrl['style'] | $ignore_style)) ||
                   ($this_ctrl['exStyle'] != $other_ctrl['exStyle']) ||
                   (!is_equal_unicode_or_id($this_ctrl['className'], $other_ctrl['className'])) ||
                   // We should have either id's or text in both
                   (is_int($this_ctrl['text']) ^ is_int($other_ctrl['text'])) ||
                   // If it's an id they should be equal
                   (is_int($this_ctrl['text']) &&
                    !is_equal_unicode_or_id($this_ctrl['text'], $other_ctrl['text'])) ||
                   // If either text is empty they should be equal
                   (!is_int($this_ctrl['text']) && ((count($this_ctrl['text']) == 0) || (count($other_ctrl['text']) == 0)) &&
                    !is_equal_unicode_or_id($this_ctrl['text'], $other_ctrl['text']));

        if ($pedantic != TRUE)
            return $generic;

        return $generic ||
               // If we have text in both they should not be equal
               (!is_int($this_ctrl['text']) && ((count($this_ctrl['text']) != 0) && (count($other_ctrl['text']) != 0)) &&
                is_equal_unicode_or_id($this_ctrl['text'], $other_ctrl['text']));
    }

    function dump($master_res = NULL)
    {
        if ($master_res)
        {
            $show = diff_sequences($this, count($this->items),
                                   $master_res, count($master_res->items),
                                   'control_equals');
        }
        else
            $show = array_fill(0, count($this->items), 1);

        dump_resource_row("", $this, $master_res, "dump_header", NULL, NULL);
        dump_resource_row("", $this, $master_res, "dump_hex", "is_hex_different", array("style", "STYLE"));
        dump_resource_row("", $this, $master_res, "dump_hex", "is_hex_different", array("exStyle", "EXSTYLE"));
        dump_resource_row("", $this, $master_res, "dump_string", NULL, array("title", "CAPTION"));
        dump_resource_row("", $this, $master_res, "dump_string", "is_string_different", array("className", "CLASS"));
        dump_resource_row("", $this, $master_res, "dump_string", "is_string_different", array("menuName", "MENU"));
        dump_resource_row("", $this, $master_res, "dump_font", NULL, NULL);
        
        $pos = 0;
        $master_pos = 0;
        for ($i = 0; $i < count($show); $i++)
        {
            dump_resource_row("", $this, $master_res, "dump_control", "is_control_different",
                array($pos, $show[$i] & 1), array($master_pos, $show[$i] & 2));

            if ($show[$i] & 1)
                $pos++;
            if ($show[$i] & 2)
                $master_pos++;
        }
    }
}

?>
