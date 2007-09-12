<?php
/**
 * Redirects to one of many URLs that have the Mono Windows installer available.
 * 
 * Usage: 
 * mono.php
 * (main usage, redirects to one of many URLs that have the Mono Windows installer available)
 * 
 * mono.php?action=showlist
 * (display a list of server and tells if the file is available for each server)
 * 
 * Copyright (c) 2006 Jonathan Ernst
 */


// Name of the file
$sFileName = "mono-1.2.1-gtksharp-2.8.3-win32-1.exe";

// Exact size of the file:
$iFileSize = 46430421;

// List of additional locations (commonly used locations are already in download.inc.php)
$aList = array("ftp://www.go-mono.com/archive/1.2.1/windows-installer/1/");

// Common code for Wine downloader scripts
require("download.inc.php");
?>
