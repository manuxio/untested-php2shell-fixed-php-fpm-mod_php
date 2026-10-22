<?php
echo "PHP_VERSION=", PHP_VERSION, "\n";
foreach (array("memory_limit", "memory_hard_limit_percent", "session.upload_progress.enabled", "max_multipart_body_parts", "expose_php", "opcache.enable") as $k) {
	echo $k, "=", var_export(ini_get($k), true), "\n";
}
echo "opcache active: ", var_export(function_exists('opcache_get_status') && (opcache_get_status(false)['opcache_enabled'] ?? false), true), "\n";
