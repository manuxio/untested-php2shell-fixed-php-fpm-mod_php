<?php
// One 64 MB str_repeat() with memory_limit=16M (the image default is -1).
register_shutdown_function(function () { echo "shutdown function ran\n"; });
ini_set('memory_limit', '16M');
echo "before\n";
$x = str_repeat('x', 64 * 1024 * 1024);
echo "after the allocation\n";
