# PHP 7.2.34 Apache/mod_php (php2shell-patched)

> **UNTESTED, UNOFFICIAL, NO WARRANTY.** This is a best-effort, hand-made backport for a
> PHP version that has been end-of-life since November 2020. It has **not** been reviewed by
> the PHP project and has only been exercised by the few functional tests in [`test/`](test/).
> PHP 7.2.34 has other known, unfixed vulnerabilities. Migrate off PHP 7.2.

A PHP **7.2.34 Apache (mod_php)** Docker image with a port of the PHP 7.4 *minimal mitigation* for
**php2shell** — [CVE-2026-109618](https://github.com/php/php-src/security/advisories/GHSA-w8hw-w9fx-j79w)
and [CVE-2026-109619](https://github.com/php/php-src/security/advisories/GHSA-6wmf-4rv5-p3rp).
It is meant as a drop-in replacement for the official `php:7.2-apache` image: downstream
Dockerfiles only need to change their `FROM` line.

## Image

```bash
docker pull ghcr.io/manuxio/untested-php2shell-fixed-php-fpm-mod_php:7.2.34-apache
```

The build recipe is the last official `php:7.2-apache` (Debian buster) Dockerfile from
[docker-library/php](https://github.com/docker-library/php) — `7.2/buster/apache/` at commit
`20ebff40`, the parent of `4908ef27` "Remove 7.2 (EOL)" — with the same base image, packages,
configure flags (`--with-apxs2`), helper scripts (`docker-php-*`, `apache2-foreground`), entrypoint,
Apache configuration (prefork MPM, `docker-php.conf`, log symlinks, envvars rewrite), `STOPSIGNAL`,
`EXPOSE 80` and `CMD`. Changes to that recipe:

- apt sources point to `archive.debian.org` (`buster`, `buster/updates`, `buster-updates`).
  The archive signatures still verify with the keys shipped in `debian:buster-slim`, so
  **signature checking is kept**. Note that today's `debian:buster-slim` is the final buster
  point release and the archive carries all buster security updates, so Debian package versions
  are newer than in the December 2020 official image.
- PHP GPG keys fetched from `hkp://keyserver.ubuntu.com:80` (the SKS pool no longer exists).
  The tarball is still checked against php.net's SHA256 and GPG signature.
- `patch` added to the (auto-purged) build dependencies; the two patches below are applied
  with `patch -p1 --fuzz=0` right after `docker-php-source extract`, before `./configure`.
  The patch files stay in `/usr/src/` for reference.
- Mitigation defaults: `/usr/local/etc/php/conf.d/zz-php2shell-mitigations.ini` (see *Behaviour changes*).
- OCI labels.

`docker-php-source extract` (used by `docker-php-ext-*`) still unpacks the **pristine**
tarball; extensions built later compile against the installed, patched headers, which is what
matters for them. Do not rebuild the statically compiled core (e.g. `session`) from that tree.

Build it yourself:

```bash
docker build -t php:7.2.34-apache-cve .
```

## Patches

### `php-7.2-CVE-2026-109618-109619.patch`

The upstream PHP 7.4 patch ([php-src@712e60f9ed](https://github.com/php/php-src/commit/712e60f9edfd03f0960fc4fc3c2c375f42b90aa2))
targets the same engine generation (Zend Engine 3), so most of it carries over; the rest was
ported by hand:

| Upstream 7.4 change | 7.2 port |
|---|---|
| OOM / allocation overflow: print the fatal error to stderr and `_exit(1)` instead of `zend_error()` + `longjmp()` (`zend_mm_safe_error_ex`) — `zend_alloc.c`, `zend_multiply.h`, `zend_strtod.c` (`Balloc`), `zend_hash.c` | Same. `zend_alloc.c`: 8 of 9 hunks as-is (only the `#include` context differs); `zend_multiply.h`, `zend_strtod.c` as-is; the three `zend_hash.c` conversions re-applied by hand (context drift) |
| String concatenation overflow checks in `ZEND_CONCAT` / `ZEND_FAST_CONCAT` (`zend_vm_def.h`, `zend_vm_execute.h`) | 7.2 has **no** overflow check in either branch of these handlers, so the check (`len > ZSTR_MAX_LEN - len2` → `zend_mm_safe_error_ex`) is added to both branches of both handlers, i.e. the same resulting code as 7.4. `zend_vm_execute.h` was verified to be byte-identical to what `zend_vm_gen.php` generates from the patched `zend_vm_def.h` |
| — | **7.2-only:** `ZSTR_MAX_OVERHEAD` / `ZSTR_MAX_LEN` backported to `zend_string.h` (introduced in 7.3, needed by the concat checks) |
| Reset per-request globals that outlive the request: `SG(request_info)` pointers, `PG(http_globals)`, `PG(modules_activated)`, `zend_llist` head/tail | `SAPI.c`, `main.c`, `zend_llist.c`: as-is |
| Reset user error/exception handlers, `EG(error_handling)`, `EG(exception)` and `EG(objects_store)` on (fast) executor shutdown | `shutdown_executor()` is structured differently in 7.2 (handlers are only cleaned in the slow path), so the same resets were placed by hand: handlers/handler stacks cleared on fast shutdown before the object store is freed, `EH_NORMAL`/`exception` reset after it, `objects_store.object_buckets = NULL; top = 1` at the end of the fast-shutdown branch |
| `session.upload_progress` forcibly disabled | `session.c`: `\|\| true` written as `\|\| 1` (no `stdbool.h` in scope in 7.2) |
| Multipart: keep only `Content-Disposition` / `Content-Type` headers, ignore duplicates, new INI `max_multipart_body_parts`, `size_t` in `substring_conf` | `rfc1867.c`, `main.c`: as-is |
| `array_init_singleton()` for superglobal sub-arrays (`php_variables.c`) + `zend_new_array_singleton()` | 7.2 has no `zend_new_array()` API: `zend_new_array_singleton()` is implemented with `_zend_hash_init()` + `nTableSize = 1`, `array_init_singleton()` added to `zend_API.h`; the four `php_variables.c` call sites converted (1 hunk as-is, 3 adapted for context) |
| `HT_HASH_RESET` SSE2 path: `memset` fallback for tables < 64 bytes (`zend_types.h`) | **Not needed / dropped:** 7.2's `HT_HASH_RESET` is a plain `memset()` with no SSE2 path or size assertion, so 1-slot tables are already safe |

**Not changed (same as upstream 7.4):** `max_execution_time`. Since PHP 7.1 the timeout
signal handler only sets `EG(timed_out)` / `EG(vm_interrupt)`; the fatal error is raised by
`zend_timeout()` at the next opcode boundary in normal execution context, not from inside the
signal handler. The "hard" timeout path (`hard_timeout`) already writes to stderr and
`_exit()`s. The 5.4 backport needed an extra SIGPROF rewrite; 7.2 does not.

### `php-7.2-mask-server-signature.patch`

Hides the PHP version in server signatures (`php-b-mnx` = PHP 7.x):

- `main/SAPI.h`: `X-Powered-By: PHP/7.2.34` → `X-Powered-By: php-b-mnx` (all SAPIs, mod_php included)
- `sapi/apache2handler/sapi_apache2.c`: Apache `Server` token `PHP/7.2.34` → `php-b-mnx`
  (only visible with `ServerTokens Full`; the image keeps Debian's default `ServerTokens OS`,
  which sends `Server: Apache/2.4.59 (Debian)` without any PHP component)

`phpversion()`, `PHP_VERSION` and `php -v` are unchanged. `expose_php = Off` still removes the
header entirely.

## Behaviour changes

- Exceeding `memory_limit`, or any allocation size overflow, **terminates the Apache child
  process** with `_exit(1)`: no shutdown functions, no destructors, the error goes to stderr
  (the container log), not to PHP's `error_log`, and the client gets an empty reply (no HTTP
  response). The prefork MPM replaces the child.
- **`memory_limit = -1` by default** (`conf.d/zz-php2shell-mitigations.ini`): there is no
  PHP-level memory cap unless you set one. Downstream images can override it with their own
  ini file, `php_admin_value` or `.htaccess`; container memory limits still apply.
- `session.upload_progress` never records progress, whatever the INI / `.htaccess` says (the
  default is also set to `0` in the ini file above, so `ini_get()` reflects reality).
- New INI `max_multipart_body_parts` (default `-1` = `max_input_vars + max_file_uploads`,
  settable per directory); when exceeded, parsing stops with a warning. Multipart part headers
  other than `Content-Disposition` / `Content-Type` are ignored, as are duplicates.
- `X-Powered-By: php-b-mnx` instead of `X-Powered-By: PHP/7.2.34`; with `ServerTokens Full`
  the `Server` header reads `Apache/2.4.59 (Debian) php-b-mnx`.
- `max_execution_time` behaves as in stock 7.2 (regular fatal error, shutdown functions run).
- There is no equivalent of FPM's `pm.max_requests = 1` in this image: the official recipe's
  Apache configuration is left untouched (`MaxConnectionsPerChild` stays at Debian's default
  `0`). Set it in your own image if you want per-request process recycling.

Other fatal errors still unwind with `longjmp()`; this is a mitigation, not a complete fix.

## Tests

```bash
sh test/run.sh php:7.2.34-apache-cve
# compare with the official image:
NET=aptest72b CT=ap72b sh test/run.sh php:7.2-apache
```

Runs Apache on a private Docker network (`aptest72` / container `ap72` by default, no
published ports) and drives it over HTTP from a `curlimages/curl` helper container
(`test/tests.sh`). Per-directory settings come from `.htaccess` files in `test/www/up/` and
`test/www/mp/`; `test/servertokens-full.conf` is mounted to make the PHP `Server` token
visible. Observed results:

| Test | Official `php:7.2-apache` | Patched |
|---|---|---|
| Defaults | `memory_limit=128M`, `upload_progress.enabled=1` | `memory_limit=-1`, `upload_progress.enabled=0`, `max_multipart_body_parts=-1` |
| `X-Powered-By` | `PHP/7.2.34` | `php-b-mnx` |
| `Server` (`ServerTokens Full`) | `Apache/2.4.38 (Debian) PHP/7.2.34` | `Apache/2.4.59 (Debian) php-b-mnx` |
| `Server` (image default) | `Apache/2.4.38 (Debian)` | `Apache/2.4.59 (Debian)` |
| Upload progress re-enabled via `.htaccess`, session cookie, `cleanup=0` | `upload_progress_prog` written to the session | nothing written |
| `max_multipart_body_parts=3` via `.htaccess`, 6 parts sent | ignored, all parts parsed | warning "Multipart body parts limit exceeded 3", only the first 3 parts parsed |
| OOM (`memory_limit=16M`, 64 MB string) | HTTP 200 with fatal error, shutdown function runs | `curl: (52) Empty reply from server`, "Fatal error: Allowed memory size…" in the container log, next requests OK |
| OOM (CLI) | fatal, shutdown function runs, exit 255 | fatal, no shutdown function, exit 1 |
| Timeout (`set_time_limit(1)` + busy loop) | fatal "Maximum execution time of 1 second exceeded", shutdown function runs, next request OK | identical to official (by design, see above) |
| Nested array input (`a[]=…&b[x][y]=…`, GET and POST) | parsed | parsed identically (exercises `array_init_singleton`) |

The PHP 7.2 `make test` suite has **not** been run.

## License

The patches modify PHP source code and are distributed under the
[PHP License 3.01](https://www.php.net/license/3_01.txt). The Dockerfile and helper scripts
are derived from [docker-library/php](https://github.com/docker-library/php) (MIT).
