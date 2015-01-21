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

if(!$sFileSuffix)
	$sFileSuffix = $sVersion;

switch($sVersion) {
case '0.0.1':
case '0.1.0':
case '0.9.0':
case '0.9.1':
case '1.0.0':
case '1.1.0':
	$sExt = 'cab';
	break;
default:
	$sExt = 'msi';
}

// Name of the file
$sFileName = sprintf('%s/%s/wine_gecko-%s.%s', $sFolder, $sVersion, $sFileSuffix, $sExt);

// Size array
$aFileSizes = array(
	'0.0.1'=>5219822,
	'0.1.0'=>5746895,
	'0.9.0'=>7806669,
	'0.9.1'=>7806837,
	'1.0.0-x86'=>8119486,
	'1.1.0-x86'=>8868851,
	'1.1.0-x86_64'=>8940997,
	'1.2.0-x86'=>12604928,
	'1.2.0-x86_64'=>12841472,
	'1.3-x86'=>13609984,
	'1.3-x86_64'=>13835776,
	'1.4-x86'=>14732288,
	'1.4-x86_64'=>14980096,
	'1.5-x86'=>15950848,
	'1.5-x86_64'=>16345088,
	'1.6-x86'=>16802816,
	'1.6-x86_64'=>17251328,
	'1.7-x86'=>16995328,
	'1.7-x86_64'=>17438720,
	'1.8-x86'=>17774592,
	'1.8-x86_64'=>18238976,
	'1.9-x86'=>19060224,
	'1.9-x86_64'=>19622400,
	'2.21-x86'=>20871680,
	'2.21-x86_64'=>21646336,
	'2.24-beta1-x86'=>22354944,
	'2.24-beta1-x86_64'=>23590400,
	'2.24-x86'=>22373888,
	'2.24-x86_64'=>23608320,
	'2.34-beta1-x86'=>28131328,
	'2.34-beta1-x86_64'=>29696000,
	'2.34-beta2-x86'=>28270080,
	'2.34-beta2-x86_64'=>29807616,
	'2.34-x86'=>28269568,
	'2.34-x86_64'=>29802496,
	'2.36-beta1-x86'=>29698560,
	'2.36-beta1-x86_64'=>31211008
);

// Exact size of the file:
$iFileSize = $aFileSizes[$sFileSuffix];
if(!$iFileSize) {
	header("HTTP/1.0 404 Not Found");
	exit;
}

// List of additional locations (commonly used locations are already in download.inc.php)
$aList = array();

// Common code for Wine downloader scripts
require("download.inc.php");
?>
