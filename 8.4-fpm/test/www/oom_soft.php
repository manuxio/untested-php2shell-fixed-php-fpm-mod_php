<?php
// Soft limit: the 16 MB concatenation result is allocated (usage stays below 2x memory_limit);
// with the fix the OOM error is raised at the next VM interrupt check.
register_shutdown_function(function () { echo "shutdown function ran\n"; });
ini_set('memory_limit', '16M');
$a = str_repeat('x', 8 * 1024 * 1024);
echo "before\n";
$b = $a . $a;
echo "after the allocation\n";
