<?php
// Hard limit: the 24 MB concatenation result would take usage above 2x memory_limit.
register_shutdown_function(function () { echo "shutdown function ran\n"; });
ini_set('memory_limit', '16M');
$a = str_repeat('x', 12 * 1024 * 1024);
echo "before\n";
$b = $a . $a;
echo "after the allocation\n";
