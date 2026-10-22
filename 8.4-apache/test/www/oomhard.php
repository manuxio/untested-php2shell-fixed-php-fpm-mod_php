<?php
register_shutdown_function(function () { echo "shutdown function ran\n"; });
ini_set('memory_limit', '16M');
echo "before\n";
// 12 MB fits under the 16M soft limit; the 36 MB concatenation result is an infallible allocation
// that crosses the hard limit (2 x memory_limit by default in the official fix)
$a = str_repeat('x', 12 * 1024 * 1024);
$b = $a . $a . $a;
echo "after (should not happen)\n";
