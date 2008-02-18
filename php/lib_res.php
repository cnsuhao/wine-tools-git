<?php

function get_word(&$data)
{
    if (strlen($data)  < 2)
        die("not enough data");
    $cx = unpack("vc", $data);
    $data = substr($data, 2);
    return $cx["c"];
}

function get_stringorid(&$data)
{
    $c1 = get_word($data);
    if ($c1 == 0xffff)
        return get_word($data);

    $ret ="";
    while ($c1)
    {
        $ret .= ($c1>=0x80 ? '?' : chr($c1));
        $c1 = get_word($data);
    }
    return $ret;
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
        else
            echo "&#x".dechex($unistr[$i]).";";
    }
    if ($quoted)
        echo "&quot;";
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

            if (strlen($data) == 0)
                break;

            if (strlen($data) < 8)
                die("Couldn't read header");
            $header = unpack("VresSize/VheaderSize", $data);
            assert($header["headerSize"] > 8);

            $len = $header["headerSize"] - 8;
            $data = fread($this->file, $len);
            if (strlen($data) < $len)
                die("Couldn't read header");

            $header["type"] = get_stringorid($data);
            $header["name"] = get_stringorid($data);
            if (($len - strlen($data)) % 4)  /* WORD padding */
                get_word($data);
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
        $out = NULL;
        if ($this->enumResources(array($this, 'load_resource_helper'), array($type, $name, $language, &$header, &$out, $ignore_sublang)))
        {
            return array($header, $out);
        }
        return FALSE;
    }
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

    function StringTable($header, $data)
    {
        $this->Resource($header);
        $this->strings = array();
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
}

function dump_header($header)
{
    var_dump($header);
    echo "<br/>";
    return FALSE;
}

?>
