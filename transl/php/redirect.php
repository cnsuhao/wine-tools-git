<?php

$url = $_REQUEST['url'];

if (strpos($url, "http://wiki.winehq.org/") === 0)
    header("Location: $url");
else
    die("Invalid address");
?>
