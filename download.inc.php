<?php
/**
 * Common code for Wine downloader scripts.
 * 
 * Copyright (c) 2006 Jonathan Ernst
 */

// List of common locations for files
$aList += array("http://switch.dl.sourceforge.net/sourceforge/wine/",
                "http://surfnet.dl.sourceforge.net/sourceforge/wine/",
                "http://citkit.dl.sourceforge.net/sourceforge/wine/",
                "http://keihanna.dl.sourceforge.net/sourceforge/wine/",
                "http://heanet.dl.sourceforge.net/sourceforge/wine/",
                "http://easynews.dl.sourceforge.net/sourceforge/wine/",
                "http://ovh.dl.sourceforge.net/sourceforge/wine/",
                "http://jaist.dl.sourceforge.net/sourceforge/wine/",
                "http://puzzle.dl.sourceforge.net/sourceforge/wine/",
                "http://nchc.dl.sourceforge.net/sourceforge/wine/",
                "http://switch.dl.sourceforge.net/sourceforge/wine/",
                "http://kent.dl.sourceforge.net/sourceforge/wine/",
                "http://optusnet.dl.sourceforge.net/sourceforge/wine/",
                "http://mesh.dl.sourceforge.net/sourceforge/wine/",
                "http://internap.dl.sourceforge.net/sourceforge/wine/",
                "http://superb-east.dl.sourceforge.net/sourceforge/wine/",
                "http://optusnet.dl.sourceforge.net/sourceforge/wine/",
                "http://superb-west.dl.sourceforge.net/sourceforge/wine/",
                "http://nchc.dl.sourceforge.net/sourceforge/wine/",
                "http://umn.dl.sourceforge.net/sourceforge/wine/",
                "http://belnet.dl.sourceforge.net/sourceforge/wine/",
                "http://ufpr.dl.sourceforge.net/sourceforge/wine/"
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
