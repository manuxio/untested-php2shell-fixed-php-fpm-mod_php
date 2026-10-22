<?php
// OPcache in FPM: the shared cache lives in the master's SHM, so it must survive the
// per-request worker recycling (pm.max_requests=1) and keep serving cached scripts.
require __DIR__ . '/arr.php';
if (!function_exists('opcache_get_status') || !($s = opcache_get_status(true)) || !$s['opcache_enabled']) {
	echo "opcache: not active\n";
	return;
}
echo "opcache: active pid=", getmypid(), " cached_scripts=", $s['opcache_statistics']['num_cached_scripts'],
	" arr.php cached=", var_export(isset($s['scripts'][__DIR__ . '/arr.php']), true),
	" hits>0=", var_export($s['opcache_statistics']['hits'] > 0, true), "\n";
