<?php
/**
 * Redirects to a URL for the Wine Mono installer
 */

// Default version if none given
$sVersion = '4.5.6';

// Suffix appended to base name of file
$sFileSuffix = '';

// Folder which contains files
$sFolder = 'wine-mono';

// Check if a specific version was passed
if(isset($_GET['v'])) {
	$sVersion = $_GET['v'];
}

if(!$sFileSuffix)
	$sFileSuffix = $sVersion;

$sExt = 'msi';

// Name of the file
$sFileName = sprintf('%s/%s/wine-mono-%s.%s', $sFolder, $sVersion, $sFileSuffix, $sExt);

// Common code for Wine downloader scripts
require("download.inc.php");
?>
