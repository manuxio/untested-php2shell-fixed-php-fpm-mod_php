#!/bin/sh
# usage: test/run.sh <image>
# Starts php-fpm from <image> on a private docker network (no published ports) and runs the
# functional tests against it over FastCGI (test/fcgi.php, run from a second container of the
# same image), then a few CLI checks. Network/container names can be overridden with NET / CT
# to avoid clashing with other test runs.
set -u
IMG=$1
NET=${NET:-fpmtest84}
CT=${CT:-fpm84}
cd "$(dirname "$0")"
T=$(pwd -W 2>/dev/null || pwd)   # pwd -W: Windows path under Git Bash
export MSYS_NO_PATHCONV=1

docker network create "$NET" >/dev/null 2>&1
docker rm -f "$CT" >/dev/null 2>&1
docker run -d --name "$CT" --network "$NET" -v "$T/www:/var/www/html:ro" "$IMG" >/dev/null
sleep 2
echo "=== image: $IMG"
echo "=== FPM pool settings (php-fpm -tt)"
docker exec "$CT" php-fpm -tt 2>&1 | grep -E 'pm\.max_requests|upload_progress|^.*\[www\]$' | sed 's/^\[[^]]*\] //' | sort -u
docker run --rm --network "$NET" -e FPM_ADDR="$CT:9000" -v "$T:/test:ro" "$IMG" sh /test/tests.sh
echo "=== FPM log (access lines, startup and normal respawn notices omitted)"
docker logs "$CT" 2>&1 | grep -v '"GET\|"POST' \
	| grep -v 'NOTICE: \(fpm is running\|ready to handle\)\|exited with code 0 after\|child [0-9]* started' | tail -20
echo "worker exits with code 0: $(docker logs "$CT" 2>&1 | grep -c 'exited with code 0 after')"
docker rm -f "$CT" >/dev/null
docker network rm "$NET" >/dev/null

echo "=== CLI: php -v (version string unchanged)"
docker run --rm --network none "$IMG" php -v | head -1
for s in oom oom_soft oom_hard; do
	echo "=== CLI: $s.php (memory_limit=16M)"
	docker run --rm --network none -v "$T/www:/w:ro" "$IMG" php /w/$s.php 2>&1
	echo "[exit $?]"
done
echo "=== CLI: opcache caches a script through the patched persist code"
docker run --rm --network none -v "$T/www:/w:ro" "$IMG" php -d opcache.enable_cli=1 -r 'require "/w/arr.php"; $s = opcache_get_status(false); echo "opcache_enabled=", var_export($s["opcache_enabled"], true), " cached_scripts=", $s["opcache_statistics"]["num_cached_scripts"], "\n";'
echo "[exit $?]"
