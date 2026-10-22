#!/bin/sh
# usage: test/run.sh <image>
# Starts Apache/mod_php from <image> on a private docker network (no published ports) and runs
# the functional tests against it over HTTP from a curl helper container, then a few CLI checks.
# Network/container names can be overridden with NET / CT to avoid clashing with other test runs.
set -u
IMG=$1
NET=${NET:-aptest82}
CT=${CT:-ap82}
CURL_IMG=${CURL_IMG:-curlimages/curl:latest}
cd "$(dirname "$0")"
T=$(pwd -W 2>/dev/null || pwd)   # pwd -W: Windows path under Git Bash
export MSYS_NO_PATHCONV=1

docker network create "$NET" >/dev/null 2>&1
docker rm -f "$CT" >/dev/null 2>&1
# servertokens-full.conf: "ServerTokens Full" so the PHP component of the Server header is visible
docker run -d --name "$CT" --network "$NET" -v "$T/www:/var/www/html" \
	-v "$T/servertokens-full.conf:/etc/apache2/conf-enabled/zz-servertokens-full.conf:ro" "$IMG" >/dev/null
sleep 3
docker run --rm --network "$NET" -e AP_HOST="$CT" -v "$T:/test:ro" --entrypoint sh "$CURL_IMG" /test/tests.sh
echo "=== Apache log"
docker logs "$CT" 2>&1 | grep -v '"GET\|"POST' | tail -20
docker rm -f "$CT" >/dev/null
docker network rm "$NET" >/dev/null

echo "=== CLI: php -v (version string unchanged)"
docker run --rm --network none "$IMG" php -v | head -1
echo "=== CLI: OOM, soft limit (memory_limit=16M, fallible 64 MB str_repeat())"
docker run --rm --network none -v "$T/www:/w:ro" "$IMG" php /w/oom.php 2>&1
echo "[exit $?]"
echo "=== CLI: OOM, hard limit (memory_limit=16M, infallible 36 MB concatenation)"
docker run --rm --network none -v "$T/www:/w:ro" "$IMG" php /w/oomhard.php 2>&1
echo "[exit $?]"
echo "=== CLI: opcache loads and caches a script through the patched persist code (enabled for the test if the image does not enable it)"
docker run --rm --network none -v "$T/www:/w:ro" "$IMG" sh -c '
	if php -m | grep -q "^Zend OPcache$"; then echo "(opcache enabled by the image)"; set --; else echo "(opcache loaded for the test)"; set -- -d zend_extension=opcache; fi
	php "$@" -d opcache.enable_cli=1 -r '\''require "/w/arr.php"; $s = opcache_get_status(false); echo "opcache_enabled=", var_export($s["opcache_enabled"], true), " cached_scripts=", $s["opcache_statistics"]["num_cached_scripts"], "\n";'\'''
echo "[exit $?]"
