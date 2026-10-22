# PHP 7.4 Apache (mod_php) — `7.4-apache/`

*Part of [untested-php2shell-fixed-php](https://github.com/manuxio/untested-php2shell-fixed-php-fpm-mod_php).
All paths below are relative to this `7.4-apache/` directory.*

> **UNTESTED, UNOFFICIAL, NO WARRANTY.** PHP 7.4 has been end-of-life since November 2022.
> These images apply the upstream PHP 7.4 *minimal mitigation* unchanged, but the build itself
> has **not** been reviewed by the PHP project and has only been exercised by the few functional
> tests in [`test/`](test/). PHP 7.4.32 / 7.4.33 have other known, unfixed vulnerabilities.
> Migrate off PHP 7.4.

PHP **7.4.32** and **7.4.33 Apache (mod_php)** Docker images with the upstream PHP 7.4 minimal
mitigation for **php2shell** —
[CVE-2026-109618](https://github.com/php/php-src/security/advisories/GHSA-w8hw-w9fx-j79w) and
[CVE-2026-109619](https://github.com/php/php-src/security/advisories/GHSA-6wmf-4rv5-p3rp).
They are meant as drop-in replacements for the official `php:7.4-apache` image (and the pinned
`php:7.4.32-apache`): downstream Dockerfiles only need to change their `FROM` line.

## Images

```bash
docker pull ghcr.io/manuxio/untested-php2shell-fixed-php-fpm-mod_php:7.4.33-apache
docker pull ghcr.io/manuxio/untested-php2shell-fixed-php-fpm-mod_php:7.4.32-apache
```

Tags follow the docker-library `<full-version>-<sapi>` convention. 7.4.33 is the final PHP 7.4
release.

## Layout

Like docker-library, one self-contained build context per version:

```text
7.4.32/   Dockerfile, docker-php-* helpers, apache2-foreground, patches, mitigation ini
7.4.33/   same files; only PHP_VERSION / PHP_URL / PHP_SHA256 and the version labels differ
test/     shared functional tests: sh test/run.sh <image>
```

The patch files are identical in both directories: none of the files they touch differ between
the 7.4.32 and 7.4.33 tarballs, and both apply with `--fuzz=0` and zero line offset to both.

Build them yourself:

```bash
cd 7.4-apache
docker build -t php:7.4.33-apache-cve 7.4.33
docker build -t php:7.4.32-apache-cve 7.4.32
```

## Build recipe

The recipe is the last official `php:7.4-apache` (Debian bullseye) Dockerfile from
[docker-library/php](https://github.com/docker-library/php) — `7.4/bullseye/apache/` at commit
`1361ba95`, the parent of `f2999de8` "Remove PHP 7.4 (EOL 28 November 2022)" — with the same base
image, packages, configure flags (`--with-apxs2`, `--disable-cgi`, `--with-pear`, ...), helper
scripts (`docker-php-*`, `apache2-foreground`), entrypoint, Apache configuration (prefork MPM,
`docker-php.conf`, log symlinks, envvars rewrite), `STOPSIGNAL`, `EXPOSE 80` and `CMD`.
The official 7.4.32 Dockerfile (`fa38b1c3` "Update 7.4 to 7.4.32") differs from it only in the
three `PHP_*` version lines, so `7.4.32/` uses the same recipe with `PHP_VERSION=7.4.32` and
php.net's SHA256 `323332c9…7864a`. Changes to the official recipe:

- apt sources point to `archive.debian.org` (`bullseye`, `bullseye-security`, `bullseye-updates`).
  Bullseye LTS ended in August 2026; `deb.debian.org` still serves the bullseye indexes, but
  security-pool downloads now return 404, so builds against the default sources fail. The archive
  signatures verify with the keys shipped in `debian:bullseye-slim`, so **signature checking is
  kept**. Note that today's `debian:bullseye-slim` is the final bullseye point release (11.11) and
  the archive carries all bullseye security/LTS updates, so Debian package versions (Apache
  included) are newer than in the November 2022 official image.
- The PHP release keys are still fetched from `keyserver.ubuntu.com` as in the original; the
  tarball is checked against php.net's SHA256 and GPG signature.
- `patch` added to the (auto-purged) build dependencies; the two patches below are applied with
  `patch -p1 --fuzz=0` right after `docker-php-source extract`, before `./configure`. The patch
  files stay in `/usr/src/` for reference.
- Mitigation defaults: `/usr/local/etc/php/conf.d/zz-php2shell-mitigations.ini` (see *Behaviour changes*).
- OCI labels.

`docker-php-source extract` (used by `docker-php-ext-*`) still unpacks the **pristine** tarball;
extensions built later compile against the installed, patched headers, which is what matters for
them. Do not rebuild the statically compiled core (e.g. `session`) from that tree.

## Patches

### `php-7.4-CVE-2026-109618-109619.patch`

The upstream fix, [php-src@712e60f9ed](https://github.com/php/php-src/commit/712e60f9edfd03f0960fc4fc3c2c375f42b90aa2)
("Avoid state corruption via bailout — Minimal mitigation for EOL version", Arnaud Le Blanc /
Ilija Tovilo), was written **for PHP 7.4** and is used **byte-for-byte unchanged**: all 17 files
apply to both 7.4.32 and 7.4.33 with `--fuzz=0`, no offsets, no adaptation. It covers:

- OOM / allocation size overflow: print the fatal error to stderr and `_exit(1)` instead of
  `zend_error()` + `longjmp()` (`zend_alloc.c`, `zend_multiply.h`, `zend_strtod.c`, `zend_hash.c`)
- string concatenation overflow checks in `ZEND_CONCAT` / `ZEND_FAST_CONCAT` (`zend_vm_def.h`,
  `zend_vm_execute.h`)
- reset of per-request state that outlives a request (`SAPI.c`, `main.c`, `zend_llist.c`) and of
  user error/exception handlers, error handling mode, pending exception and object store on
  executor shutdown (`zend_execute_API.c`)
- `session.upload_progress` forcibly disabled (`session.c`)
- multipart parsing: only `Content-Disposition` / `Content-Type` part headers kept, duplicates
  ignored, new INI `max_multipart_body_parts`, `size_t` lengths (`rfc1867.c`, `main.c`)
- superglobal sub-arrays created as 1-slot tables via `array_init_singleton()` /
  `zend_new_array_singleton()` and the matching `HT_HASH_RESET` small-table fix
  (`php_variables.c`, `zend_API.h`, `zend_hash.[ch]`, `zend_types.h`)

**Remi Collet's backport** ([rpms/php/php74](https://git.remirepo.net/cgit/rpms/php/php74.git),
`php-7.4-cve-2026-109618.patch`, 7.4.33-31, cherry-picked from php-src `b62095c7`) was compared
line by line: its added/removed code is identical to upstream except that it omits the
`max_multipart_body_parts` hunks and has `isspace((unsigned char)…)` in two context/removed lines.
Both differences exist only because Remi's 7.4 tree already carries earlier security backports
(CVE-2023-0662 `max_multipart_body_parts`, `isspace` casts) that are not in the php.net 7.4.33
tarball. The resulting code is the same, so **no Remi delta was adopted**.

### `php-7.4-mask-server-signature.patch`

Hides the PHP version in server signatures (`php-b-mnx` = PHP 7.x):

- `main/SAPI.h`: `X-Powered-By: PHP/7.4.x` → `X-Powered-By: php-b-mnx` (all SAPIs, mod_php included)
- `sapi/apache2handler/sapi_apache2.c`: Apache `Server` token `PHP/7.4.x` → `php-b-mnx`
  (only visible with `ServerTokens Full`; the image keeps Debian's default `ServerTokens OS`,
  which sends `Server: Apache/2.4.x (Debian)` without any PHP component). This also changes the
  Apache startup log line (`… (Debian) php-b-mnx configured`).

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
- `X-Powered-By: php-b-mnx` instead of `X-Powered-By: PHP/7.4.x`; with `ServerTokens Full`
  the `Server` header reads `Apache/2.4.x (Debian) php-b-mnx`.
- `max_execution_time` is **not** changed by the upstream 7.4 patch and behaves as in stock 7.4:
  the timeout signal handler only sets `EG(timed_out)` / `EG(vm_interrupt)`, and the regular
  fatal error ("Maximum execution time … exceeded") is raised by `zend_timeout()` at the next
  opcode boundary in normal execution context; shutdown functions run and the child keeps
  serving. The "hard" timeout path already writes to stderr and `_exit()`s.
- There is no equivalent of FPM's `pm.max_requests = 1` in this image: the official recipe's
  Apache configuration is left untouched (`MaxConnectionsPerChild` stays at Debian's default
  `0`). Set it in your own image if you want per-request process recycling.

Other fatal errors still unwind with `longjmp()`; this is a mitigation, not a complete fix.

## Tests

```bash
sh test/run.sh php:7.4.33-apache-cve
sh test/run.sh php:7.4.32-apache-cve
# compare with the official image:
NET=aptest74o CT=ap74o sh test/run.sh php:7.4-apache
```

Runs Apache on a private Docker network (`aptest74` / container `ap74` by default, no published
ports) and drives it over HTTP from a `curlimages/curl` helper container (`test/tests.sh`).
Per-directory settings come from `.htaccess` files in `test/www/up/` and `test/www/mp/`;
`test/servertokens-full.conf` is mounted to make the PHP `Server` token visible. A final step
runs the CLI OOM case. Observed results:

| Test | Official `php:7.4-apache` (7.4.33) | Patched 7.4.33 and 7.4.32 (identical results) |
|---|---|---|
| Defaults | `memory_limit=128M`, `upload_progress.enabled=1`, no `max_multipart_body_parts` | `memory_limit=-1`, `upload_progress.enabled=0`, `max_multipart_body_parts=-1` |
| `X-Powered-By` | `PHP/7.4.33` | `php-b-mnx` |
| `Server` (`ServerTokens Full`) | `Apache/2.4.54 (Debian) PHP/7.4.33` | `Apache/2.4.67 (Debian) php-b-mnx` |
| Version in `Server` / `X-Powered-By` | leaked | not leaked (body `PHP_VERSION` unchanged) |
| Upload progress re-enabled via `.htaccess`, session cookie, `cleanup=0` | `upload_progress_prog` written to the session | nothing written |
| `max_multipart_body_parts=3` via `.htaccess`, 6 parts sent | ignored, all parts parsed | warning "Multipart body parts limit exceeded 3", only the first 3 parts parsed (`PHP_SESSION_UPLOAD_PROGRESS,f1,f2`, no file) |
| OOM (`memory_limit=16M`, 64 MB string) | HTTP 200 with fatal error, shutdown function runs | `curl: (52) Empty reply from server`, "Fatal error: Allowed memory size…" in the container log, next two requests OK (new child PIDs) |
| OOM (CLI) | fatal, shutdown function runs, exit 255 | fatal, no shutdown function, exit 1 |
| Timeout (`set_time_limit(1)` + busy loop) | HTTP 200, fatal "Maximum execution time of 1 second exceeded", shutdown function runs, next request OK | identical to official (upstream 7.4 patch leaves timeouts alone, see above) |
| Nested array input (`a[]=…&b[x][y]=…`, GET and POST) | parsed | parsed identically (exercises `array_init_singleton`) |
| `php -m` | — | identical module list to official; `docker-php-ext-install bcmath` works |

Debian packages come from the final bullseye archive, so Apache is 2.4.67 (`2.4.67-1~deb11u3`)
instead of the 2.4.54 shipped in the 2022 official image.

The PHP 7.4 `make test` suite has **not** been run.

## License

The patches modify PHP source code and are distributed under the
[PHP License 3.01](https://www.php.net/license/3_01.txt). The Dockerfile and helper scripts
are derived from [docker-library/php](https://github.com/docker-library/php) (MIT).
