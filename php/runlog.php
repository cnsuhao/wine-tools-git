<?php
include("config.php");

header("Content-type: text/plain");
$f = fopen("$DATAROOT/dumps/run.log", "r");
fpassthru($f);
?>