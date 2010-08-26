<?php
/**
 * Common code for Wine downloader scripts.
 * 
 * Copyright (c) 2006 Jonathan Ernst
 */

// List of common locations for files
$aList += array("http://freefr.dl.sourceforge.net/project/wine/",
                "http://heanet.dl.sourceforge.net/project/wine/",
                "http://garr.dl.sourceforge.net/project/wine/",
                "http://mesh.dl.sourceforge.net/project/wine/",
                "http://puzzle.dl.sourceforge.net/project/wine/",
                "http://switch.dl.sourceforge.net/project/wine/",
                "http://kent.dl.sourceforge.net/project/wine/",
                "http://netcologne.dl.sourceforge.net/project/wine/",
                "http://ignum.dl.sourceforge.net/project/wine/",
                "http://ovh.dl.sourceforge.net/project/wine/",
                "http://sunet.dl.sourceforge.net/project/wine/",
                "http://surfnet.dl.sourceforge.net/project/wine/",
                "http://citylan.dl.sourceforge.net/project/wine/",
                "http://space.dl.sourceforge.net/project/wine/",
                "http://iweb.dl.sourceforge.net/project/wine/",
                "http://voxel.dl.sourceforge.net/project/wine/",
                "http://cdnetworks-kr-1.dl.sourceforge.net/project/wine/",
                "http://cdnetworks-kr-2.dl.sourceforge.net/project/wine/",
                "http://nchc.dl.sourceforge.net/project/wine/",
                "http://ncu.dl.sourceforge.net/project/wine/",
                "http://jaist.dl.sourceforge.net/project/wine/",
                "http://superb-sea2.dl.sourceforge.net/project/wine/",
                "http://softlayer.dl.sourceforge.net/project/wine/",
                "http://biznetnetworks.dl.sourceforge.net/project/wine/",
                "http://ufpr.dl.sourceforge.net/project/wine/",
                "http://cdnetworks-us-2.dl.sourceforge.net/project/wine/",
                "http://cdnetworks-us-1.dl.sourceforge.net/project/wine/",
                "http://waix.dl.sourceforge.net/project/wine/",
                "http://internode.dl.sourceforge.net/project/wine/",
                "http://transact.dl.sourceforge.net/project/wine/"
               );
              

function is_downloadable($sUrl)
{
    global $iFileSize;
    $parse = parse_url($sUrl);
    // open a socket connection
    if($fp = @fsockopen($parse['host'], 80, $errno, $errstr, 10))
    {
        // set request
        $get = "HEAD ".$parse['path']." HTTP/1.1\r\n".
               "Host: ".$parse['host']."\r\n".
               "Connection: close\r\n\r\n";
        fputs($fp, $get);
        while(!feof($fp))
        {
            // get ONLY header information
            $header .= fgets($fp, 128);
        }
        fclose($fp);
        // match file size
        preg_match('/Content-Length:\s([0-9].+?)\s/', $header, $matches);
        $iSize = intval($matches[1]);
        if($iSize == $iFileSize) return TRUE;
    }
    return FALSE;
}


if($_REQUEST['action']=="showlist")
{
    echo "<h2>List of mirrors available for file ".$sFileName." (".$iFileSize." bytes)</h2>";
    foreach($aList as $sLocation)
    {
        echo $sLocation.": ";
        if(is_downloadable($sLocation.$sFileName))
            echo "<font color=\"green\">online</font>";
        else
            echo "<font color=\"red\">offline</font>";
        echo "\n<br />";
        flush();
    }
} else
{
    $iRand = rand(0, (sizeof($aList)-1));
    $sUrl = $aList[$iRand].$sFileName;
    // we continue as long as we didn't find a working mirror and we didn't tried all the mirrors
    while(!is_downloadable($sUrl) && sizeof($aAlreadyTried)<sizeof($aList))
    {
        $aAlreadyTried[$iRand] = true;
        // we loop until we take a random mirror that we didn't already tried ; of course if we have already tried all mirrors we stop
        while($aAlreadyTried[$iRand] == true && sizeof($aAlreadyTried)<sizeof($aList))
            $iRand = rand(0, (sizeof($aList)-1));
        $sUrl = $aList[$iRand].$sFileName;
    }
    header("Location: ".$sUrl);
}
?>
