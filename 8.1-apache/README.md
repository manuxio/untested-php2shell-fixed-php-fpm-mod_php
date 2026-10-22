# PHP 8.1 Apache (mod_php) — php2shell-patched images

> **UNTESTED, UNOFFICIAL, NO WARRANTY.** PHP 8.1 has been end-of-life since 31 December 2025 and
> php.net has **not** released a fix for php2shell for this branch. These images apply the
> backport published by Remi Collet's RPM repository (remirepo), lightly refreshed for each
> source tree. Neither the patch adaptation nor these images have been reviewed by the PHP
> project or by Remi Collet; they have only been exercised by the functional tests in
> [`test/`](test/). PHP 8.1.27 and 8.1.28 also carry other known, unfixed vulnerabilities that
> later 8.1 releases (and, for 8.1.34, later remirepo patches) address. Migrate off PHP 8.1.

PHP **8.1 Apache (mod_php)** Docker images with the *minimal mitigation* for **php2shell** —
[CVE-2026-109618](https://github.com/php/php-src/security/advisories/GHSA-w8hw-w9fx-j79w) and
[CVE-2026-109619](https://github.com/php/php-src/security/advisories/GHSA-6wmf-4rv5-p3rp).
Each one is meant as a drop-in replacement for the corresponding official `php:<version>-apache`
image: downstream Dockerfiles only need to change their `FROM` line.

| Directory | Replaces | Planned image |
|---|---|---|
| [`8.1.27/`](8.1.27/) | `php:8.1.27-apache` (Debian bookworm) | `ghcr.io/manuxio/untested-php2shell-fixed-php-fpm-mod_php:8.1.27-apache` |
| [`8.1.28/`](8.1.28/) | `php:8.1.28-apache` (Debian bookworm) | `ghcr.io/manuxio/untested-php2shell-fixed-php-fpm-mod_php:8.1.28-apache` |
| [`8.1.34/`](8.1.34/) | `php:8.1.34-apache` (Debian trixie) — **final 8.1 release** (php.net, 18 Dec 2025) | `ghcr.io/manuxio/untested-php2shell-fixed-php-fpm-mod_php:8.1.34-apache` |

There is no `latest` tag. Each directory is a self-contained build context:

```bash
docker build -t php:8.1.27-apache-cve 8.1.27/
docker build -t php:8.1.28-apache-cve 8.1.28/
docker build -t php:8.1.34-apache-cve 8.1.34/
```

## Build recipes

Each `Dockerfile` is the official [docker-library/php](https://github.com/docker-library/php)
`8.1/<suite>/apache/Dockerfile` (plus helper scripts) from the last commit that pinned that
PHP version, i.e. the recipe the last published official image of that tag was built from:

| Version | Recipe | Commit | Next commit (changes the version) |
|---|---|---|---|
| 8.1.27 | `8.1/bookworm/apache` | `9635283a0b0f63b477f159d5a8ed2c5eebe0b050` | `feeb0150` "Update to 8.1.28 (security release)" |
| 8.1.28 | `8.1/bookworm/apache` | `bfcdcb3fa5d6e3ba82950fcdd4078d6b6e027fbb` | `52062af5` "Update to 8.3.8, 8.2.20, 8.1.29" |
| 8.1.34 | `8.1/trixie/apache` | `5c037abaf9dc0095e29807c048d9d1b97e6a9716` | `9cf5f245` "Remove EOL 8.1" |

(The official `php:8.1.34-apache` tag points to the trixie variant; the 8.1.34 recipe also
enables OPcache by default, which these images keep.)

Base image, packages, configure flags (`--with-apxs2`, `--disable-cgi`, …), helper scripts
(`docker-php-*`, `apache2-foreground`), entrypoint, Apache configuration (prefork MPM,
`docker-php.conf`, log symlinks, envvars rewrite), `STOPSIGNAL`, `EXPOSE 80`, `CMD`, GPG keys,
keyserver and the official `PHP_SHA256` values are unchanged. The **only** changes are:

- the two patches below, copied to `/usr/src/` and applied with `patch -p1 --fuzz=0` right
  after `docker-php-source extract`, before `./configure` (`patch` is already present through
  `dpkg-dev` from `PHPIZE_DEPS`, so no build dependency was added);
- `/usr/local/etc/php/conf.d/zz-php2shell-mitigations.ini` (see *Behaviour changes*);
- OCI labels.

No EOL/archive fixups were needed: bookworm and trixie are live, and the original
`keyserver.ubuntu.com` still serves the PHP release keys. Because the Debian base images and
packages are today's point releases, Debian package versions are newer than in the official
images (e.g. Apache 2.4.68 on bookworm instead of 2.4.57 / 2.4.59, 2.4.69 on trixie instead of
2.4.65).

`docker-php-source extract` (used by `docker-php-ext-*`) still unpacks the **pristine**
tarball; extensions built later compile against the installed, patched headers, which is what
matters for them. Do not rebuild the statically compiled core (e.g. `session`) from that tree.

## Patches

### `php-8.1-cve-2026-109618.patch` — provenance

Source: **Remi Collet's `php81` package, `php-8.1.34-6.remi.src.rpm`**
(<https://rpms.remirepo.net/SRPMS/php-8.1.34-6.remi.src.rpm>, sha256
`3d99c712a6480df26f4e3dcfd8818ceba5bbfd22bf1c325912c5c17c8cb4c18d`), git
[rpms/php/php81](https://git.remirepo.net/cgit/rpms/php/php81.git/) commit
`0ae74cf7722e15cfb8d7b113d12dbf04a39440df` (21 Oct 2026, "Mitigation fix Avoid state corruption
via bailout — CVE-2026-109618, CVE-2026-109619"), `Patch214: php-8.1-cve-2026-109618.patch`
(sha256 `5eff7cb9cf020dc451d9c74e1962cbc23e6dabb9f2a75402f6188e8e191603c6`, identical in the
SRPM and in git). The patch is the upstream "Minimal mitigation for EOL version" by Arnaud Le
Blanc / Ilija Tovilo (header: "cherry picked from commit 7901b4f9b139…"), the 8.1 counterpart of
the PHP 7.4 mitigation [php-src@712e60f9ed](https://github.com/php/php-src/commit/712e60f9edfd03f0960fc4fc3c2c375f42b90aa2).
No fallback/own backport was needed.

Adaptation: Remi applies it on top of 8.1.34 **after** his other backports. One of them,
`php-cve-2026-7258.patch` (ctype `(unsigned char)` casts, an unrelated CVE), changes context
lines in `main/rfc1867.c`, so 2 of Remi's 4 `rfc1867.c` hunks do not apply to pristine
tarballs (not even 8.1.34). The only edit is in three lines of those two hunks:
`isspace((unsigned char)*value)` / `isspace((unsigned char)*strend)` → `isspace(*value)` /
`isspace(*strend)`, i.e. what the pristine source has; the ctype fix itself is **not** imported.
Every other hunk is content-identical to Remi's. The file in each directory was then
regenerated against that version's pristine tarball so it applies with `--fuzz=0` and without
offsets:

- **8.1.34**: same hunk line numbers as Remi's file.
- **8.1.28**: line offsets only (`Zend/zend_alloc.c` hunks 6–9: −1/−4 lines; the three
  `ext/zend_test` `.phpt` files: −1 line).
- **8.1.27**: as 8.1.28, plus offsets in `main/php_variables.c` (−1 to −13 lines; 8.1.28
  changed that file for the `__Host-`/`__Secure-` cookie fix).

The patch file headers keep Remi's/upstream's commit message and add a note with this provenance.

What it changes (8.1):

| Change | Files |
|---|---|
| OOM / allocation size overflow: print "Fatal error: …" to stderr and `_exit(1)` instead of `zend_error()` + `longjmp()` (`zend_mm_safe_error_ex`); `zend_mm_panic` / `zend_out_of_memory` use `_exit` | `zend_alloc.c/.h`, `zend_multiply.h`, `zend_strtod.c` (`Balloc`), `zend_hash.c` |
| String concatenation overflow checks in `ZEND_CONCAT` / `ZEND_FAST_CONCAT` | `zend_vm_def.h`, `zend_vm_execute.h` |
| Reset per-request state that outlives the request: user error/exception handlers and their stacks, `EG(record_errors/num_errors/errors)`, `EG(error_handling)`, `EG(exception)`, `EG(objects_store)` after fast shutdown; `SG(request_info)` pointers, `PG(http_globals)`, `PG(modules_activated)`, last error | `zend_execute_API.c`, `SAPI.c`, `main.c` |
| `session.upload_progress` forcibly disabled (`\|\| true`) | `ext/session/session.c` |
| Multipart: keep only `Content-Disposition` / `Content-Type` part headers, ignore duplicates; `size_t` lengths in `substring_conf` | `main/rfc1867.c` |
| `array_init_singleton()` / `zend_new_array_singleton()` for superglobal sub-arrays; `HT_HASH_RESET` SSE2 path safe for 1-slot tables | `php_variables.c`, `zend_API.h`, `zend_hash.c/.h`, `zend_types.h` |
| **8.1 only (not in the 7.4 patch):** OPcache publishes class-name CE-cache slots in shared memory only after `ZCSG(map_ptr_last)` is published, and discards them if a persist window is left via bailout | `ext/opcache/ZendAccelerator.c/.h`, `zend_file_cache.c`, `zend_persist.c` |
| Test expectations for three observer tests | `ext/zend_test/tests/*.phpt` |

Compared with the 7.4 minimal mitigation, the 8.1 patch does **not** add
`max_multipart_body_parts`: PHP 8.1 has it natively since 8.1.17 (CVE-2023-0662), with the same
semantics (default `-1` = `max_input_vars + max_file_uploads`, `PHP_INI_PERDIR`). It also has no
`zend_llist.c` hunk. `max_execution_time` handling is unchanged, as in 7.4.

### `php-8.1-mask-server-signature.patch`

Hides the PHP version in server signatures (`php-c-mnx` = PHP 8.x):

- `main/SAPI.h`: `X-Powered-By: PHP/8.1.x` → `X-Powered-By: php-c-mnx` (all SAPIs, mod_php included)
- `sapi/apache2handler/sapi_apache2.c`: Apache `Server` token `PHP/8.1.x` → `php-c-mnx`
  (only visible with `ServerTokens Full`; the images keep Debian's default `ServerTokens OS`,
  which sends `Server: Apache/2.4.x (Debian)` without any PHP component)

`phpversion()`, `PHP_VERSION` and `php -v` are unchanged. `expose_php = Off` still removes the
header entirely. The patch is identical for all three versions.

## Behaviour changes

- Exceeding `memory_limit`, or any allocation size overflow, **terminates the Apache child
  process** with `_exit(1)`: no shutdown functions, no destructors, no output flush, the error
  goes to stderr (the container log), not to PHP's `error_log`, and the client gets an empty
  reply (no HTTP response). The prefork MPM replaces the child. The official 8.1 fix behaves
  exactly like the 7.4 minimal mitigation here — tested, see below.
- **`memory_limit = -1` by default** (`conf.d/zz-php2shell-mitigations.ini`): there is no
  PHP-level memory cap unless you set one. Downstream images can override it with their own
  ini file, `php_admin_value` or `.htaccess`; container memory limits still apply.
- `session.upload_progress` never records progress, whatever the INI / `.htaccess` says (the
  default is also set to `0` in the ini file above, so `ini_get()` reflects reality).
- Multipart part headers other than `Content-Disposition` / `Content-Type` are ignored, as are
  duplicates. `max_multipart_body_parts` behaves as in stock 8.1 (native).
- `X-Powered-By: php-c-mnx` instead of `X-Powered-By: PHP/8.1.x`; with `ServerTokens Full`
  the `Server` header reads `Apache/2.4.x (Debian) php-c-mnx`.
- `max_execution_time` behaves as in stock 8.1 (regular fatal error, shutdown functions run).
- There is no equivalent of FPM's `pm.max_requests = 1`: the official Apache configuration is
  left untouched (`MaxConnectionsPerChild` stays at Debian's default `0`). Set it in your own
  image if you want per-request process recycling.

Other fatal errors still unwind with `longjmp()`; this is a mitigation, not a complete fix.

## Tests

```bash
sh test/run.sh php:8.1.27-apache-cve
sh test/run.sh php:8.1.28-apache-cve
sh test/run.sh php:8.1.34-apache-cve
# compare with an official image:
NET=aptest81o CT=ap81o sh test/run.sh php:8.1.34-apache
```

Runs Apache on a private Docker network (`aptest81` / container `ap81` by default, no
published ports) and drives it over HTTP from a `curlimages/curl` helper container
(`test/tests.sh`), then runs a few CLI checks. Per-directory settings come from `.htaccess`
files in `test/www/up/` and `test/www/mp/`; `test/servertokens-full.conf` is mounted to make the
PHP `Server` token visible. Observed results (all three patched images behave identically
except where noted; the official images were run with the same harness):

| Test | Official `php:8.1.{27,28,34}-apache` | Patched |
|---|---|---|
| Defaults | `memory_limit=128M`, `upload_progress.enabled=1`, `max_multipart_body_parts=-1` | `memory_limit=-1`, `upload_progress.enabled=0`, `max_multipart_body_parts=-1`; OPcache active in mod_php on 8.1.34 only (as in the official recipes) |
| `X-Powered-By` | `PHP/8.1.27` / `PHP/8.1.28` / `PHP/8.1.34` | `php-c-mnx` |
| `Server` (`ServerTokens Full`) | `Apache/2.4.57 (Debian) PHP/8.1.27`, `Apache/2.4.59 (Debian) PHP/8.1.28`, `Apache/2.4.65 (Debian) PHP/8.1.34` | `Apache/2.4.68 (Debian) php-c-mnx` (bookworm), `Apache/2.4.69 (Debian) php-c-mnx` (trixie) |
| Upload progress re-enabled via `.htaccess`, session cookie, `cleanup=0` | `upload_progress_prog` written to the session | nothing written to the session; fields and file still parsed |
| `max_multipart_body_parts=3` via `.htaccess`, 6 parts sent | warning "Multipart body parts limit exceeded 3", first 3 parts parsed (+ "Session cookie cannot be sent" warning from upload progress) | same limit warning and same 3 parts (native 8.1 feature); no session warning |
| OOM (`memory_limit=16M`, 64 MB string) | HTTP 200 with fatal error, shutdown function runs | `curl: (52) Empty reply from server`, "Fatal error: Allowed memory size of 16777216 bytes exhausted…" in the container log, next requests OK (served by replacement children) |
| OOM (CLI) | fatal, shutdown function runs, exit 255 | fatal on stderr, no shutdown function, exit 1 |
| Timeout (`set_time_limit(1)` + busy loop) | fatal "Maximum execution time of 1 second exceeded", shutdown function runs, next request OK | identical to official |
| Nested array input (`a[]=…&b[x][y]=…`, GET and POST) | parsed | parsed identically (exercises `array_init_singleton`) |
| OPcache CLI (`opcache.enable_cli=1`, cache one script) | works | works (patched persist path; enabled by the image on 8.1.34, loaded for the test on 8.1.27/8.1.28) |

The PHP `make test` suite has **not** been run.

## License

The patches modify PHP source code and are distributed under the
[PHP License 3.01](https://www.php.net/license/3_01.txt). The Dockerfiles and helper scripts
are derived from [docker-library/php](https://github.com/docker-library/php) (MIT).
