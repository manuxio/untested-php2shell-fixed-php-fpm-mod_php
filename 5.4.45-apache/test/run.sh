#!/bin/sh
# usage: test/run.sh <image>
# Starts Apache/mod_php from <image> on a private docker network (no published ports)
# and runs the functional tests against it over HTTP from a curl container.
set -u
IMG=$1
NET=apachetest54
CT=ap54
CURL_IMG=${CURL_IMG:-curlimages/curl:latest}
cd "$(dirname "$0")"
T=$(pwd -W 2>/dev/null || pwd)   # pwd -W: Windows path under Git Bash
export MSYS_NO_PATHCONV=1

docker rm -f $CT >/dev/null 2>&1
docker network create $NET >/dev/null 2>&1
docker run -d --name $CT --network $NET -v "$T/www:/var/www/html" "$IMG" >/dev/null
i=0; until docker run --rm --network $NET "$CURL_IMG" -sf -o /dev/null "http://$CT/ok.php" 2>/dev/null; do
  i=$((i+1)); [ $i -gt 20 ] && { echo "apache did not come up"; docker logs $CT; exit 1; }; sleep 1
done
docker run --rm --network $NET -v "$T:/test:ro" --entrypoint sh "$CURL_IMG" /test/tests.sh $CT
echo "=== session file /tmp/sess_testsess (test 1)"
docker exec $CT sh -c 'cat /tmp/sess_testsess; echo' 2>&1
echo "=== Apache error log (stderr)"
docker logs $CT 2>&1 >/dev/null | tail -20
docker rm -f $CT >/dev/null
docker network rm $NET >/dev/null
