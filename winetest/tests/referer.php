<?php
  if (strlen($_SERVER['HTTP_REFERER']))
      echo $_SERVER['HTTP_REFERER'];
  else
      echo "no referer set";
?>
