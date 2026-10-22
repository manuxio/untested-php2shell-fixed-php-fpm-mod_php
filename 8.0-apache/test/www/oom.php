<?php
register_shutdown_function(function () { echo "shutdown function ran\n"; });
ini_set('memory_limit', '16M');
echo "before\n";
$x = str_repeat('x', 64 * 1024 * 1024);
echo "after (should not happen)\n";
