<?php
/**
 * Redirects to one of many URLs that have the MozillaActiveX control available.
 * 
 * Usage: 
 * mozactivex.php
 * (main usage, redirects to one of many URLs that have the MozillaActiveX control available)
 * 
 * mozactivex.php?action=showlist
 * (display a list of server and tells if the file is available for each server)
 * 
 * Copyright (c) 2005-2006 Jonathan Ernst
 */


// Name of the file
$sFileName = "MozillaControl1712-ReactOS.exe";

// Exact size of the file:
$iFileSize = 4735160;

// List of additional locations (commonly used locations are already in download.inc.php)
$aList = array();

// Common code for Wine downloader scripts
require("download.inc.php");
?>
