<?php
include_once("config.php");
include_once("lib.php");

$summary = fopen("$DATAROOT/langs/summary", "r");
while ($line = fgets($summary, 1024))
{
    if (!preg_match("/LANG ([0-9a-f]+:[0-9a-f]+) ([0-9]+) ([0-9]+) ([0-9]+) ([0-9]+)/", $line, $m))
    {
        die("couldn't parse line $line");
    }

    if (has_lang_flag($m[1], "hide"))
        continue;
    
    $sum = $m[2]+0;
    $transl[$m[1]] = $m[3];
    $missing[$m[1]] = $m[4];
    $errors[$m[1]] = $m[5];    
}
?>
<html>
<h1>Wine translation statistics</h1>
<table border="1">
<tr><th></th><th>Language</th><th>Translated</th><th>Missing</th><th>Errors</th><th>&nbsp;</th></tr>
<?php
function draw_bar($tr, $err, $sum)
{
    $tr_len = floor(($tr*300)/$sum);
    $err_len = floor(($err*300)/$sum);
    if ($err_len == 0 && $err > 0)
    {
        $err_len++;
        if ($tr_len > 1)
            $tr_len--;
    }
    $miss_len = 300 - $tr_len - $err_len;
    echo '<td style="background-color: #D1DAF9">';
    echo "<img src=\"img/bar0.gif\" height=\"15\" width=\"$tr_len\">";
    echo "<img src=\"img/bar1.gif\" height=\"15\" width=\"$err_len\">";
//    echo "<img src=\"img/bar6.gif\" height=\"15\" width=\"$miss_len\">";
    echo "</td></tr>";
}

arsort($transl, SORT_NUMERIC);
$nr = 1;
$missing_sum = 0;
$errors_sum = 0;
$transl_sum = 0;
$serial = 0;
$transl_keys = array_keys($transl);
for ($i = 0; $i < count($transl); $i++)
{
    $langid = $transl_keys[$i];
    $value = $transl[$langid];
    echo "<tr>";
    if ($serial == 0)
    {
        for ($j = $i; $j < count($transl); $j++)
            if ($transl[$langid] != $transl[$transl_keys[$j]])
                break;
        $serial = $j - $i;
        echo "<td rowspan=\"$serial\" style=\"text-align: center\">$nr";
        echo "</td>";
    }
    echo "<td><a href=\"lang.php?lang=$langid\">".get_lang_name($langid)."</a></td>";
    printf("<td>%d (%.1f%%)</td>", $value, ($value*100)/$sum);
    echo "<td>".$missing[$langid]."</td><td>".$errors[$langid]."</td>\n";
    draw_bar($value, $errors[$langid], $sum);
    
    $nr++;
    $missing_sum += $missing[$langid];
    $errors_sum += $errors[$langid];
    $transl_sum += $value;
    $serial--;
}
?>
<tr><td></td><td><b>Sum:</b></td>
<td><?php printf("%d (%.1f%%)", $transl_sum, ($transl_sum*100)/(($nr-1)*$sum)) ?></td>
<td><?php echo $missing_sum ?></td>
<td><?php echo $errors_sum ?></td>
<?php draw_bar($transl_sum, $errors_sum, ($nr-1)*$sum) ?>
</table>

<?php
if ($time = filemtime("$DATAROOT/langs/summary"))
{
    echo "<p><small>Generated on ".gmdate("j M Y, G:i:s T", $time)."</small></p>";
}
?>
</html>