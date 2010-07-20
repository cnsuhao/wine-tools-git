<?php
$branch = $_REQUEST['branch'];
if ($branch != "stable") $branch = "master";
$DATAROOT = $branch;
?>
