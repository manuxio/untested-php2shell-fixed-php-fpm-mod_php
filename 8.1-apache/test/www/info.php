<?php
foreach (array("memory_limit", "session.upload_progress.enabled", "max_multipart_body_parts", "expose_php", "opcache.enable") as $k) {
	echo $k, "=", var_export(ini_get($k), true), "\n";
}
echo "opcache_active=", var_export(function_exists("opcache_get_status") && is_array(@opcache_get_status(false)), true), "\n";
