<?php

class Stopwatch
{
    function Stopwatch($name = "")
    {
        $this->time = 0;
        $this->name = "";
        $this->running = TRUE;
        $this->time = $this->get_microtime();
    }

    function get_microtime()
    {
        $time = split(" ", microtime());
        return $time[0] + $time[1];
    }

    function pause()
    {
        if (!$this->running)
            die("illegal stopwatch stop");
        $this->running = FALSE;
        $this->time = $this->get_microtime() - $this->time;
    }

    function resume()
    {
        if ($this->running)
            die("illegal stopwatch stop");
        $this->running = TRUE;
        $this->time = $this->get_microtime() - $this->time;
    }

    function stop()
    {
        $this->pause();
        echo "Stopwatch ".$this->name." run for ".$this->time."<br/>";
    }

    var $time;
    var $running;
    var $name;
}

?>