set -u
F="php /test/fcgi.php ${FPM_ADDR:-fpm72:9000}"
mp() { # build multipart body with N text fields + 1 file, plus progress field first
  b=XyZb; n=$1
  printf -- "--$b\r\nContent-Disposition: form-data; name=\"PHP_SESSION_UPLOAD_PROGRESS\"\r\n\r\nprog\r\n"
  i=1; while [ $i -le $n ]; do printf -- "--$b\r\nContent-Disposition: form-data; name=\"f$i\"\r\nX-Junk: aaaa\r\n\r\nv$i\r\n"; i=$((i+1)); done
  printf -- "--$b\r\nContent-Disposition: form-data; name=\"up\"; filename=\"a.txt\"\r\nContent-Type: text/plain\r\n\r\nhello\r\n--$b--\r\n"
}
echo "=== 0. defaults + response headers (X-Powered-By must be masked)"
$F info.php < /dev/null
export CTYPE="multipart/form-data; boundary=XyZb"
export COOKIE="PHPSESSID=testsess"
echo "=== 1. multipart normal (4 fields + file), upload_progress explicitly RE-ENABLED per request, cleanup off"
mp 4 | $F post.php "session.upload_progress.enabled=1;session.upload_progress.cleanup=0;session.save_path=/tmp"
unset COOKIE
echo "=== 2. multipart with max_multipart_body_parts=3 (6 parts sent)"
mp 4 | $F parts.php "max_multipart_body_parts=3;display_errors=1;display_startup_errors=1"
echo "=== 3. OOM in worker (memory_limit=16M set by the script; image default is -1)"
unset CTYPE
$F oom.php < /dev/null
echo "=== 4. next requests after OOM (must be served; PIDs differ because of pm.max_requests=1)"
$F ok.php < /dev/null
$F ok.php < /dev/null
echo "=== 5. max_execution_time in worker (set_time_limit(1) + busy loop)"
$F loop.php < /dev/null
echo "=== 6. next request after timeout"
$F ok.php < /dev/null
echo "=== 7. nested array input vars (superglobal sub-arrays now start as 1-slot hash tables)"
printf 'a[]=1&a[]=2&a[]=3&b[x][y]=1&b[x][z]=2&b[w]=3&c=4' | $F arr.php
