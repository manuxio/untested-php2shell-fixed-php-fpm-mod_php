#!/bin/sh
# usage: test/run.sh <image>
# Starts php-fpm from <image> and runs the functional tests against it over FastCGI.
set -u
IMG=$1
cd "$(dirname "$0")"
T=$(pwd -W 2>/dev/null || pwd)   # pwd -W: Windows path under Git Bash
export MSYS_NO_PATHCONV=1

docker network create fpmtest >/dev/null 2>&1
docker rm -f fpm >/dev/null 2>&1
docker run -d --name fpm --network fpmtest -v "$T/www:/var/www/html" "$IMG" >/dev/null
sleep 2
docker run --rm --network fpmtest -v "$T:/test" "$IMG" sh /test/www/tests.sh
echo "=== FPM log"
docker logs fpm 2>&1 | grep -v '"GET\|"POST' | tail -15
docker rm -f fpm >/dev/null
docker network rm fpmtest >/dev/null
