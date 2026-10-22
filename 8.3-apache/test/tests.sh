set -u
U="http://${AP_HOST:-ap83}"
C="curl -sS -m 30"
mp() { # build multipart body with N text fields + 1 file, plus progress field first
  b=XyZb; n=$1
  printf -- "--$b\r\nContent-Disposition: form-data; name=\"PHP_SESSION_UPLOAD_PROGRESS\"\r\n\r\nprog\r\n"
  i=1; while [ $i -le $n ]; do printf -- "--$b\r\nContent-Disposition: form-data; name=\"f$i\"\r\nX-Junk: aaaa\r\n\r\nv$i\r\n"; i=$((i+1)); done
  printf -- "--$b\r\nContent-Disposition: form-data; name=\"up\"; filename=\"a.txt\"\r\nContent-Type: text/plain\r\n\r\nhello\r\n--$b--\r\n"
}
post() { mp 4 | $C -H "Content-Type: multipart/form-data; boundary=XyZb" -H "Cookie: PHPSESSID=testsess" --data-binary @- "$1"; echo "[curl exit $?]"; }
get() { out=$($C -i "$1"); rc=$?; printf '%s\n' "$out" | tr -d '\r' | grep -v '^Date:\|^Content-Length:\|^Content-Type:\|^Connection:\|^Keep-Alive:\|^Vary:\|^$'; echo "[curl exit $rc]"; }

echo "=== 0. defaults + response headers (X-Powered-By and Server must be masked)"
get "$U/info.php"
echo "=== 1. multipart normal (4 fields + file), upload_progress explicitly RE-ENABLED via .htaccess, cleanup off"
post "$U/up/post.php"
echo "=== 2. multipart with max_multipart_body_parts=3 via .htaccess (6 parts sent)"
post "$U/mp/parts.php"
echo "=== 3a. OOM, soft limit (memory_limit=16M set by the script; image default is -1): fallible 64 MB str_repeat()"
get "$U/oom.php"
echo "=== 3b. OOM, hard limit: infallible 36 MB concatenation with memory_limit=16M"
get "$U/oomhard.php"
echo "=== 4. next requests after OOM (must be served)"
get "$U/ok.php"
get "$U/ok.php"
echo "=== 5. max_execution_time in mod_php child (set_time_limit(1) + busy loop)"
get "$U/loop.php"
echo "=== 6. next request after timeout"
get "$U/ok.php"
echo "=== 7. nested array input vars (superglobal sub-arrays now start as 1-slot hash tables)"
$C -g --data 'a[]=1&a[]=2&a[]=3&b[x][y]=1&b[x][z]=2&b[w]=3&c=4' "$U/arr.php?g[]=1&g[]=2&h[k][]=x"; echo "[curl exit $?]"
