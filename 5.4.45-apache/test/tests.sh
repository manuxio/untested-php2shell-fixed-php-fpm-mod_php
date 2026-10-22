# Runs inside a curl container on the same docker network as the Apache container.
# usage: sh tests.sh <host>
set -u
H=${1:-ap54}
req() { # req <path> [curl args...] ; every call is a fresh connection
  p=$1; shift
  curl -sS --max-time 20 "$@" "http://$H/$p"
  echo "[curl exit=$? (0=ok, 52=empty reply: server closed connection without response)]"
}
mp() { # multipart body: PHP_SESSION_UPLOAD_PROGRESS field, N text fields (with junk header), 1 file
  b=XyZb; n=$1
  printf -- "--$b\r\nContent-Disposition: form-data; name=\"PHP_SESSION_UPLOAD_PROGRESS\"\r\n\r\nprog\r\n"
  i=1; while [ $i -le $n ]; do printf -- "--$b\r\nContent-Disposition: form-data; name=\"f$i\"\r\nX-Junk: aaaa\r\n\r\nv$i\r\n"; i=$((i+1)); done
  printf -- "--$b\r\nContent-Disposition: form-data; name=\"up\"; filename=\"a.txt\"\r\nContent-Type: text/plain\r\n\r\nhello\r\n--$b--\r\n"
}
CT="Content-Type: multipart/form-data; boundary=XyZb"

echo "=== S. server signature (expect X-Powered-By: php-a-mnx, Server contains php-a-mnx, no PHP/5.4.45)"
hdr=$(curl -sS -D - -o /dev/null "http://$H/ok.php" | tr -d '\r')
echo "$hdr" | grep -iE '^(server|x-powered-by):'
echo "$hdr" | grep -qx 'X-Powered-By: php-a-mnx' && echo "PASS X-Powered-By masked" || echo "FAIL X-Powered-By"
echo "$hdr" | grep -i '^server:' | grep -q 'php-a-mnx' && echo "PASS Server contains php-a-mnx" || echo "FAIL Server lacks php-a-mnx"
echo "$hdr" | grep -iE '^(server|x-powered-by):' | grep -qiE 'PHP/|5\.4\.45' && echo "FAIL real PHP version exposed" || echo "PASS real PHP version not exposed"
echo "=== 0. baked-in defaults (expect memory_limit=-1, upload_progress.enabled=0)"
req defaults.php
echo "=== 1. multipart normal (4 fields + file), upload_progress EXPLICITLY RE-ENABLED via .htaccess, cleanup off, session cookie"
mp 4 | req progress/post.php -H "$CT" -H "Cookie: PHPSESSID=testsess" --data-binary @-
echo "=== 2. multipart with max_multipart_body_parts=3 (6 parts sent)"
mp 4 | req maxparts/post.php -H "$CT" --data-binary @-
echo "=== 3. OOM in apache child"
req oom.php
echo "=== 4. next requests after OOM (new connections)"
req ok.php
req ok.php
echo "=== 5. max_execution_time in apache child"
req loop.php
echo "=== 6. next request after timeout"
req ok.php
