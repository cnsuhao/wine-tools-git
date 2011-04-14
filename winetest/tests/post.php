<?php

/*
 * Simple POST test script used by Wine Regression tests
 */

header("Content-Type: text/plain");

if (is_array($_POST) and count($_POST) > 0)
{
    foreach ($_POST as $name => $value)
    {
        echo "$name => $value\n";
    }
}
else
{
    echo "FAILED";
}

?>
