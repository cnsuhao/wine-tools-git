<?php
/**
 * Redirects to one of many URLs that have the Wine Gecko installer available.
 * 
 * Usage: 
 * winegecko.php
 * (main usage, redirects to one of many URLs that have the Wine Gecko installer available)
 * 
 * winegecko.php?action=showlist
 * (display a list of server and tells if the file is available for each server)
 * 
 * Copyright (c) 2006 Jonathan Ernst
 */

// Chek if a specific version was passed
if(isset($_GET['v']))
	$sVersion = $_GET['v'];

// Name of the file
$sFileName = "wine_gecko".($sVersion?'-'.$sVersion:'').".cab";

// Size array
$aFileSizes = array(
	'default'=>5219822,
	'0.0.1'=>5219822,
	'0.1.0'=>5746895,
	'0.9.0'=>7806669,
	'0.9.1'=>7806837
);

// Exact size of the file:
$iFileSize = ($sVersion?$aFileSizes[$sVersion]:$aFileSizes['default']);

// List of additional locations (commonly used locations are already in download.inc.php)
$aList = array();

// Common code for Wine downloader scripts
require("download.inc.php");
?>
