<?php

//include_once("stopwatch.php");

$CONSTS["RT_MENU"] = 4;
$CONSTS["RT_STRING"] = 6;

$CONSTS["MF_CHECKED"]   = 0x0008;
$CONSTS["MF_POPUP"]     = 0x0010;
$CONSTS["MF_END"]       = 0x0080;
$CONSTS["MF_SEPARATOR"] = 0x0800;

$CONSTS["MFT_DISABLED"] =   0x3;

function get_word(&$data)
{
    if (strlen($data)  < 2)
        die("not enough data");
    $cx = unpack("vc", $data);
    $data = substr($data, 2);
    return $cx["c"];
}

function get_stringorid($data, &$pos)
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
        if (($unistr[$i] >= ord('a') && $unistr[$i] < ord('z'))
                || ($unistr[$i] >= ord('A') && $unistr[$i] < ord('Z'))
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
            $header["type"] = get_stringorid($data, $strpos);
            $header["name"] = get_stringorid($data, $strpos);
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

    function load_resource_helper($header, $f, $params)
    {
        $curr_lang = ($params[5] ? ($header["language"] & 0x3ff) : $header["language"]); /* check the ignore_sublang */
        if ($header["type"] == $params[0] && $header["name"] == $params[1] && $curr_lang == $params[2])
        {
            $params[3] = $header;
            $params[4] = fread($f, $header["resSize"]);
            return TRUE;
        }
        return FALSE;
    }

    function loadResource($type, $name, $language, $ignore_sublang = FALSE)
    {
//        $sw = new Stopwatch();
/*      too slow
        if ($this->enumResources(array($this, 'load_resource_helper'), array($type, $name, $language, &$header, &$out, $ignore_sublang)))
        {
            return array($header, $out);
        }*/
        
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
            $res_type = get_stringorid($data, $strpos);
            if ($res_type == $type)
            {
                $res_name = get_stringorid($data, $strpos);
                if ($res_name == strtoupper($name))
                {
                    if ($strpos & 3)  /* DWORD padding */
                        $strpos += 2;
                    $data = substr($data, $strpos);
                    $header = unpack("VdataVersion/vmemoryOptions/vlanguage/Vversion/Vcharacteristics", $data);

                    $curr_lang = ($ignore_sublang ? ($header["language"] & 0x3ff) : $header["language"]); /* check the ignore_sublang */
                    if ($curr_lang == $language)
                    {
                        fseek($this->file, $pos + $headerSize);
                        $out = fread($this->file, $resSize);
//                        $sw->stop();
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
    
    function dump($master_res = NULL)
    {
        for ($i=0; $i<16; $i++) {
            $extra = "";

            $uni_str = $this->strings[$i];
            if ($master_res)
            {
                $master_uni_str = $master_res->strings[$i];
                if ((!$master_uni_str && $uni_str) || ($master_uni_str && !$uni_str))
                    $extra = " style=\"background-color: #ffb8d0\"";
            }
    
            echo "<tr$extra><td valign=\"top\">".(($this->table_id-1)*16+$i)."</td>";
            echo "<td>";

            dump_unicode_or_empty($uni_str);

            if ($master_res)
            {
                echo "</td><td>";
                dump_unicode_or_empty($master_uni_str);
            }
            echo "</td></tr>\n";
        }

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

    /* O(n^2) time and O(n^2) space algorithm. Menus are small so this should be OK */
    function diff_menus(&$res2)
    {
        $out = array();
        $tabdyn = array_fill(0, count($this->items) + 1,
                    array_fill(0, count($res2->items) + 1,
                        array(0, 0)));

        for ($i = 1; $i <= count($this->items); $i++)
        {
            for ($j = 1; $j <= count($res2->items); $j++)
            {
                if (($this->items[$i-1]["id"] == $res2->items[$j-1]["id"]) &&
                    ($this->items[$i-1]["level"] == $res2->items[$j-1]["level"]) &&
                    (($this->items[$i-1]["resinfo"]&1) == ($res2->items[$j-1]["resinfo"]&1)))
                {
                    $tabdyn[$i][$j] = array($tabdyn[$i-1][$j-1][0] + 1, 3);
                } else
                {
                    if ($tabdyn[$i][$j-1][0] > $tabdyn[$i-1][$j][0])
                        $tabdyn[$i][$j] = array($tabdyn[$i][$j-1][0], 2);
                    else
                        $tabdyn[$i][$j] = array($tabdyn[$i-1][$j][0], 1);
                    
                }
            }
        }
        
        $i = count($this->items);
        $j = count($res2->items);
        while ($i > 0 || $j > 0) {
            $step = $tabdyn[$i][$j][1];
            if ($i == 0)
                $step |= 2;
            if ($j == 0)
                $step |= 1;

            $out[] = $step;

            if ($step & 1)
                $i--;
            if ($step & 2)
                $j--;
        }
        return array_reverse($out);
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
            while (array_pop($tstate) === FALSE)
                ;
            $tstate[] = TRUE;
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

    function dump($master_res = NULL)
    {
        if ($master_res)
            $show = $this->diff_menus($master_res);
        else
            $show = array_fill(0, count($this->items), 1);

        $tstate = array(TRUE);
        $tstate_master = array(TRUE);
        $pos = 0;
        $master_pos = 0;
        for ($i=0; $i<count($show); $i++) {
            $extra = "";

            if ($master_res)
            {
                if ($show[$i] != 3 || $this->items[$pos]["state"] != $master_res->items[$master_pos]["state"])
                    $extra = " style=\"background-color: #ffb8d0\"";
            }

            $id = ($show[$i] & 1 ? $this->items[$pos]["id"] : $master_res->items[$pos]["id"]);
            echo "<tr$extra><td valign=\"top\">$id</td>"; /* FIXME */
            echo "<td>";

            if ($show[$i] & 1)
            {
                $this->handle_indent($tstate, $this->items[$pos]["resinfo"]);
                $this->dump_title($this->items[$pos]);
                $pos++;
            }
            else
                $this->handle_indent($tstate, NULL);

            if ($master_res)
            {
                echo "</td><td>";
                if ($show[$i] & 2)
                {
                    $this->handle_indent($tstate_master, $master_res->items[$master_pos]["resinfo"]);
                    $this->dump_title($master_res->items[$master_pos]);
                    $master_pos++;
                }
                else
                    $this->handle_indent($tstate_master, NULL);
            }
            echo "</td></tr>\n";
        }

    }
    
}

?>
