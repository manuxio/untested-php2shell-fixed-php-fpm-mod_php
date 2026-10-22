<?php
register_shutdown_function(function () { echo "shutdown function ran\n"; });
set_time_limit(1);
echo "before\n";
while (true) { $a = md5(mt_rand()); }
