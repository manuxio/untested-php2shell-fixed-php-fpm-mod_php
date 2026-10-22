#!/bin/sh
# usage: test/run.sh <image>
# Starts php-fpm from <image> on a private docker network (no published ports) and runs the
# functional tests against it over FastCGI (test/fcgi.php, run from a second container of the
# same image), then a few CLI checks. Network/container names can be overridden with NET / CT
# to avoid clashing with other test runs.
set -u
IMG=$1
NET=${NET:-fpmtest81}
CT=${CT:-fpm81}
cd "$(dirname "$0")"
T=$(pwd -W 2>/dev/null || pwd)   # pwd -W: Windows path under Git Bash
export MSYS_NO_PATHCONV=1

cleanup() { docker rm -f "$CT" >/dev/null 2>&1; docker network rm "$NET" >/dev/null 2>&1; }
cleanup
docker network create "$NET" >/dev/null
docker run -d --name "$CT" --network "$NET" -v "$T/www:/var/www/html:ro" "$IMG" >/dev/null
sleep 2
echo "=== image: $IMG"
echo "=== FPM pool settings (php-fpm -tt)"
docker exec "$CT" php-fpm -tt 2>&1 | grep -E 'pm\.max_requests|^.*\[www\]$' | sed 's/^\[[^]]*\] //' | sort -u
echo "=== php-fpm.d include order"
docker exec "$CT" ls /usr/local/etc/php-fpm.d/
docker run --rm --network "$NET" -e FPM_ADDR="$CT:9000" -v "$T:/test:ro" "$IMG" sh /test/tests.sh
echo "=== FPM log (access lines, startup and normal respawn notices omitted)"
docker logs "$CT" 2>&1 | grep -v '"GET\|"POST' \
	| grep -v 'NOTICE: \(fpm is running\|ready to handle\)\|exited with code 0 after\|child [0-9]* started' | tail -20
echo "worker exits with code 0: $(docker logs "$CT" 2>&1 | grep -c 'exited with code 0 after')"
docker rm -f "$CT" >/dev/null

# Images that do not enable OPcache (8.1.27/8.1.28, as in the official recipes): repeat the FPM
# OPcache check with the extension loaded on the php-fpm command line.
if ! docker run --rm --network none "$IMG" php -m | grep -q '^Zend OPcache$'; then
	echo "=== OPcache not enabled by the image: FPM again with -d zend_extension=opcache"
	docker run -d --name "$CT" --network "$NET" -v "$T/www:/var/www/html:ro" "$IMG" php-fpm -d zend_extension=opcache >/dev/null
	sleep 2
	docker run --rm --network "$NET" -v "$T:/test:ro" "$IMG" sh -c \
		"for i in 1 2 3; do php /test/fcgi.php $CT:9000 opc.php < /dev/null | grep '^opcache'; done"
	docker rm -f "$CT" >/dev/null
fi
docker network rm "$NET" >/dev/null

echo "=== CLI: php -v (version string unchanged)"
docker run --rm --network none "$IMG" php -v | head -1
echo "=== CLI: OOM (memory_limit=16M, 64 MB string)"
docker run --rm --network none -v "$T/www:/w:ro" "$IMG" php /w/oom.php 2>&1
echo "[exit $?]"
echo "=== CLI: opcache caches a script through the patched persist code (loaded for the test if the image does not enable it)"
docker run --rm --network none -v "$T/www:/w:ro" "$IMG" sh -c '
	if php -m | grep -q "^Zend OPcache$"; then echo "(opcache enabled by the image)"; set --; else echo "(opcache loaded for the test)"; set -- -d zend_extension=opcache; fi
	php "$@" -d opcache.enable_cli=1 -r '\''require "/w/arr.php"; $s = opcache_get_status(false); echo "opcache_enabled=", var_export($s["opcache_enabled"], true), " cached_scripts=", $s["opcache_statistics"]["num_cached_scripts"], "\n";'\'''
echo "[exit $?]"
