#!/bin/sh
# usage: test/run.sh <image>
# Starts php-fpm from <image> on a private docker network (no published ports) and runs the
# functional tests against it over FastCGI. Network/container names can be overridden with
# NET / CT to avoid clashing with other test runs.
set -u
IMG=$1
NET=${NET:-fpmtest72}
CT=${CT:-fpm72}
cd "$(dirname "$0")"
T=$(pwd -W 2>/dev/null || pwd)   # pwd -W: Windows path under Git Bash
export MSYS_NO_PATHCONV=1

docker network create "$NET" >/dev/null 2>&1
docker rm -f "$CT" >/dev/null 2>&1
docker run -d --name "$CT" --network "$NET" -v "$T/www:/var/www/html" "$IMG" >/dev/null
sleep 2
docker run --rm --network "$NET" -e FPM_ADDR="$CT:9000" -v "$T:/test" "$IMG" sh /test/www/tests.sh
echo "=== FPM log"
docker logs "$CT" 2>&1 | grep -v '"GET\|"POST' | tail -20
docker rm -f "$CT" >/dev/null
docker network rm "$NET" >/dev/null
