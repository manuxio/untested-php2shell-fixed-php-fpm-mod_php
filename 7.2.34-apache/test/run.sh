#!/bin/sh
# usage: test/run.sh <image>
# Starts Apache/mod_php from <image> on a private docker network (no published ports) and runs
# the functional tests against it over HTTP from a curl helper container. Network/container
# names can be overridden with NET / CT to avoid clashing with other test runs.
set -u
IMG=$1
NET=${NET:-aptest72}
CT=${CT:-ap72}
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
