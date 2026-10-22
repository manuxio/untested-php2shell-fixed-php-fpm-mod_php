<?php
foreach (array("memory_limit", "session.upload_progress.enabled", "max_multipart_body_parts", "expose_php") as $k) {
	echo $k, "=", var_export(ini_get($k), true), "\n";
}
