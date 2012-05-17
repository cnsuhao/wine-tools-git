<?php
/**
 * Redirects to a URL for the Wine Mono installer
 */

// Default version if none given
$sVersion = '0.0.4';

// Suffix appended to base name of file
$sFileSuffix = '';

// Folder which contains files
$sFolder = 'Wine%20Mono';

// Check if a specific version was passed
if(isset($_GET['v'])) {
	$sVersion = $_GET['v'];
}

if(!$sFileSuffix)
	$sFileSuffix = $sVersion;

$sExt = 'msi';

// Name of the file
$sFileName = sprintf('%s/%s/wine-mono-%s.%s', $sFolder, $sVersion, $sFileSuffix, $sExt);

// Size array
$aFileSizes = array(
	'0.0.4'=>44408320
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
