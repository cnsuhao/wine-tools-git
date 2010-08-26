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

// Default version if none given
$sVersion = '0.0.1';

// Suffix appended to base name of file
$sFileSuffix = '';

// Folder which contains wine gecko files
$sFolder = 'Wine%20Gecko';

// Check if a specific version was passed
if(isset($_GET['v'])) {
	$sVersion = $_GET['v'];

	if(isset($_GET['arch']))
		$sFileSuffix = $sVersion.'-'.$_GET['arch'];
}

// Name of the file
$sFileName = sprintf('%s/%s/wine_gecko-%s.cab', $sFolder, $sVersion, $sFileSuffix ? $sFileSuffix : $sVersion);

// Size array
$aFileSizes = array(
	'0.0.1'=>5219822,
	'0.1.0'=>5746895,
	'0.9.0'=>7806669,
	'0.9.1'=>7806837,
	'1.0.0-x86'=>8119486,
	'1.1.0-x86'=>8868851,
	'1.1.0-x86_64'=>8940997
);

// Exact size of the file:
$iFileSize = $aFileSizes[$sFileSuffix ? $sFileSuffix : $sVersion];
if(!$iFileSize) {
	header("HTTP/1.0 404 Not Found");
	exit;
}

// List of additional locations (commonly used locations are already in download.inc.php)
$aList = array();

// Common code for Wine downloader scripts
require("download.inc.php");
?>
