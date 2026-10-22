<?php
require __DIR__ . '/../post.php';
echo "session.upload_progress.enabled=", ini_get('session.upload_progress.enabled'), " (re-enabled by .htaccess)\n";
