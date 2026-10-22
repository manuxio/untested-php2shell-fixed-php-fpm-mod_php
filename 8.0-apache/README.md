# PHP 8.0 Apache (mod_php): 8.0.24, 8.0.26, 8.0.28 with php2shell fixes

> **UNTESTED, UNOFFICIAL, NO WARRANTY.** These images apply an unofficial (third-party) backport to a
> PHP branch that has been end-of-life since 26 November 2023. Neither the backport nor these images
> have been reviewed by the PHP project. They have only been exercised by the functional tests in
> [`test/`](test/). PHP 8.0.24, 8.0.26 and 8.0.28 all have other known, unfixed vulnerabilities
> (8.0.24 and 8.0.26 even lack fixes that later 8.0.x releases shipped). Migrate off PHP 8.0.

These are PHP **8.0.24, 8.0.26 and 8.0.28 Apache (mod_php)** Docker images with the PHP 8.0
*minimal mitigation* for **php2shell**:
[CVE-2026-109618](https://github.com/php/php-src/security/advisories/GHSA-w8hw-w9fx-j79w)
and [CVE-2026-109619](https://github.com/php/php-src/security/advisories/GHSA-6wmf-4rv5-p3rp).
Each one is meant as a drop-in replacement for the official `php:<version>-apache` image, so
downstream Dockerfiles only need to change their `FROM` line.

## Images

| Version | Directory | Image |
|---|---|---|
| 8.0.24 | [`8.0.24/`](8.0.24/) | `ghcr.io/manuxio/untested-php2shell-fixed-php-fpm-mod_php:8.0.24-apache` |
| 8.0.26 | [`8.0.26/`](8.0.26/) | `ghcr.io/manuxio/untested-php2shell-fixed-php-fpm-mod_php:8.0.26-apache` |
| 8.0.28 | [`8.0.28/`](8.0.28/) | `ghcr.io/manuxio/untested-php2shell-fixed-php-fpm-mod_php:8.0.28-apache` |

Every version directory is a self-contained build context:

```bash
docker build -t php:8.0.28-apache-cve 8.0.28
```

### Build recipe

All three images use the last official `php:8.0-apache` Dockerfile from
[docker-library/php](https://github.com/docker-library/php): `8.0/bullseye/apache/` at commit
`df4636ca`, which is the parent of `4d3ed4a9` "Remove PHP 8.0 (EOL 26 November 2023)". That recipe
built 8.0.30. These images keep its Debian bullseye base image, packages, configure flags
(`--with-apxs2 --disable-cgi`, …), helper scripts (`docker-php-*` and `apache2-foreground`, taken
verbatim), entrypoint, Apache configuration (prefork MPM, `docker-php.conf`, log symlinks, envvars
rewrite), `STOPSIGNAL`, `EXPOSE 80` and `CMD`.

The official 8.0.24 and 8.0.26 images were built in 2022 from earlier revisions of that recipe.
These images use the final revision for all three versions. The changes to that recipe are:

- **`PHP_VERSION`, `PHP_URL` and `PHP_SHA256`** are pinned per directory. The SHA256 values are
  php.net's official ones, and the tarballs are still verified against php.net's GPG signatures
  using the recipe's 8.0 release-manager keys and `keyserver.ubuntu.com`, as in the official
  recipe.
- **apt sources point to `archive.debian.org`** (`bullseye`, `bullseye-security`,
  `bullseye-updates`). bullseye is EOL, and deb.debian.org now publishes `bullseye-security`
  indexes whose pool files return 404, for example
  `xz-utils_5.2.5-2.1~deb11u2`. The archive signatures still verify with the keys shipped in
  `debian:bullseye-slim`, so **signature checking is kept**. Today's base image and archive are the
  final bullseye state, so Debian package versions are newer than in the original images. For
  example, Apache is 2.4.67 instead of 2.4.54 (8.0.24) or 2.4.56 (8.0.28).
- **`patch` is added** to the build dependencies, which are purged automatically. The patches below
  are applied with `patch -p1 --fuzz=0` right after `docker-php-source extract` and before
  `./configure`. The patch files stay in `/usr/src/` for reference.
- **Mitigation defaults** are added in `/usr/local/etc/php/conf.d/zz-php2shell-mitigations.ini`
  (see *Behaviour changes*).
- **OCI labels** are added.

`docker-php-source extract`, which `docker-php-ext-*` uses, still unpacks the **pristine**
tarball. Extensions built later compile against the installed, patched headers, which is what
matters for them. Do not rebuild the statically compiled core (for example `session`) from that
tree.

## Patches

| File | 8.0.24 | 8.0.26 | 8.0.28 |
|---|---|---|---|
| `php-8.0-cve-2023-0662.patch` (prerequisite) | ✓ | ✓ | — (already in 8.0.28) |
| `php-8.0-cve-2026-109618.patch` | ✓ | ✓ | ✓ |
| `php-8.0-mask-server-signature.patch` | ✓ | ✓ | ✓ |

The same file is copied byte for byte into every directory that uses it. They are applied in the
order shown in the table.

### `php-8.0-cve-2026-109618.patch`: Remi Collet's PHP 8.0 backport

This is the PHP 8.0 backport of the upstream fix, *"Avoid state corruption via bailout. Minimal
mitigation for EOL version"* by Arnaud Le Blanc and Ilija Tovilo. It is the 8.0 counterpart of the
PHP 7.4 fix [php-src@712e60f9ed](https://github.com/php/php-src/commit/712e60f9edfd03f0960fc4fc3c2c375f42b90aa2).
Remi Collet publishes it in [remirepo](https://rpms.remirepo.net/):

- **Git:** [git.remirepo.net `rpms/php/php80.git`](https://git.remirepo.net/cgit/rpms/php/php80.git/),
  commit `838396b441d54bfcdac0f5767cd7887b3b6c9742` (2026-10-21, *"Mitigation fix Avoid state
  corruption via bailout CVE-2026-109618, CVE-2026-109619"*). It adds the file
  `php-8.0-cve-2026-109618.patch`, applied as `Patch238` in `php80.spec`
  (`%patch -P238 -p1 -b .cve109618`).
- **SRPM:** `https://rpms.remirepo.net/SRPMS/php-8.0.30-21.remi.src.rpm`
  (sha256 `91e06faef5fd0213b7212383aa6537f950e486730eed2b533b5fa6846f6ce9c6`). The patch inside it
  is byte-identical to the git file.
- **The original file** is kept unmodified at
  [`upstream/remi-php80-8.0.30-21-php-8.0-cve-2026-109618.patch`](upstream/)
  (sha256 `223db552bbc02b138911949b792495deaba6efc64d79a3a839d4f5a6c2099a56`). Its header reads
  `(cherry picked from commit 2b394bfbf31133a8e6b1df69eddf3d3bbd309267)`. That php-src commit is
  not (yet) visible on GitHub.

Remi applies this patch to 8.0.30 **after** about 40 other backported security patches. One of them,
`php-cve-2026-7258.patch` (`Patch231`, *"Consistently pass unsigned char to ctype.h functions"*),
changes two lines that the php2shell patch uses as pre-image or context in `main/rfc1867.c`. As a
result, the original file does not apply to a pristine 8.0.x tree: 2 of the 4 `rfc1867.c` hunks
fail, even on pristine 8.0.30. The file shipped here is Remi's file with **only those two pre-image
lines** changed back to the pristine source. Every added and removed line of the fix is unchanged:

```diff
--- upstream/remi-php80-8.0.30-21-php-8.0-cve-2026-109618.patch
+++ 8.0.28/php-8.0-cve-2026-109618.patch
@@ -896 +896 @@
--			do { value++; } while (isspace((unsigned char)*value));
+-			do { value++; } while (isspace(*value));
@@ -935 +935 @@
- 		while (*strend && !isspace((unsigned char)*strend)) {
+ 		while (*strend && !isspace(*strend)) {
```

The line that the patch re-adds keeps Remi's `(unsigned char)` cast, which is harmless. CVE-2026-7258
itself is **not** included here. With this change, the patch applies with `--fuzz=0` to 8.0.24,
8.0.26 and 8.0.28. Some hunks apply at a line offset because Remi's tree contains the extra
patches. After patching, every touched file is identical across the three versions, except for
pre-existing upstream differences between 8.0.24 and 8.0.26 in `zend_vm_*.h` and `session.c`.
On 8.0.24 and 8.0.28, `Zend/zend_vm_execute.h` was verified to be byte-identical to what
`zend_vm_gen.php` generates from the patched `zend_vm_def.h`.

What the patch does (17 files):

- **OOM and allocation overflow** (`zend_alloc.c`, `zend_multiply.h`, `zend_strtod.c`,
  `zend_hash.c`): the fatal error is printed to stderr, then `_exit(1)`. This replaces
  `zend_error()` + `longjmp()` (`zend_mm_safe_error_ex`).
- **String concatenation overflow checks** in `ZEND_CONCAT` / `ZEND_FAST_CONCAT`
  (`zend_vm_def.h`, `zend_vm_execute.h`).
- **Per-request globals are reset** when they outlive the request: `SG(request_info)` pointers,
  `PG(http_globals)`, `PG(modules_activated)` and the `zend_llist` head/tail (`SAPI.c`, `main.c`,
  `zend_llist.c`).
- **Executor shutdown resets** user error/exception handlers, `EG(error_handling)`,
  `EG(exception)` and `EG(objects_store)` (`zend_execute_API.c`).
- **`session.upload_progress` is forcibly disabled** (`session.c`).
- **Multipart parsing** keeps only `Content-Disposition` / `Content-Type` part headers and ignores
  duplicates. `substring_conf` uses `size_t` (`rfc1867.c`).
- **`array_init_singleton()`** is used for superglobal sub-arrays (`php_variables.c`,
  `zend_API.h`, `zend_hash.[ch]`). `HT_HASH_RESET` gets a `memset` fallback for small tables
  (`zend_types.h`).

The 7.4 patch also adds the `max_multipart_body_parts` INI setting. The 8.0 patch does not,
because 8.0.28+ already has it (see next section).

### `php-8.0-cve-2023-0662.patch` (8.0.24 and 8.0.26 only)

The php2shell mitigation relies on `max_multipart_body_parts` to bound multipart parsing. The
upstream 7.4 fix adds this setting itself, and the 8.0 fix assumes it exists. It was introduced in
**PHP 8.0.28** as the fix for CVE-2023-0662 / GHSA-54hq-v5wp-fqgv, so 8.0.24 and 8.0.26 do not
have it. Without it, the 8.0 php2shell patch would leave those two versions without the multipart
part limit. This file therefore contains the two official php-src commits from the `PHP-8.0` branch
that 8.0.28 shipped:

- `e45850c195dcd5534394cf357a3f776d4916b655` *Fix repeated warning for file uploads limit exceeding*
- `716de0cff539f46294ef70fe75d548cd66766370` *Introduce max_multipart_body_parts INI*

The code hunks (`main/main.c`, `main/rfc1867.c`) are verbatim. The FPM test-suite files of
`716de0cf` (`sapi/fpm/tests/*`) are omitted. They are not part of this image, and
`sapi/fpm/tests/tester.inc` does not apply to 8.0.24. After this patch, `main/rfc1867.c` and
`main/main.c` of 8.0.24 and 8.0.26 are identical to 8.0.28's.

This prerequisite is **not** part of Remi's patch. It was added for these images, and it is the
only per-version difference.

### `php-8.0-mask-server-signature.patch`

This patch hides the PHP version in server signatures (`php-c-mnx` = PHP 8.x):

- `main/SAPI.h`: `X-Powered-By: PHP/8.0.x` → `X-Powered-By: php-c-mnx` (all SAPIs, mod_php included).
- `sapi/apache2handler/sapi_apache2.c`: the Apache `Server` token `PHP/8.0.x` → `php-c-mnx`.
  This token is only visible with `ServerTokens Full`. The image keeps Debian's default
  `ServerTokens OS`, which sends `Server: Apache/2.4.67 (Debian)` without any PHP component.

`phpversion()`, `PHP_VERSION` and `php -v` are unchanged. `expose_php = Off` still removes the
header entirely.

## Behaviour changes

- **OOM kills the Apache child.** Exceeding `memory_limit`, or any allocation size overflow,
  terminates the child process with `_exit(1)`. No shutdown functions or destructors run, and the
  error goes to stderr (the container log), not to PHP's `error_log`. The client gets an empty
  reply (no HTTP response), and the prefork MPM replaces the child. In the CLI, the exit code is 1
  instead of 255.
- **`memory_limit = -1` by default** (`conf.d/zz-php2shell-mitigations.ini`), so there is no
  PHP-level memory cap unless you set one. Downstream images can override it with their own ini
  file, `php_admin_value` or `.htaccess`. Container memory limits still apply.
- **`session.upload_progress` never records progress**, whatever the INI or `.htaccess` says. The
  default is also set to `0` in the ini file above, so `ini_get()` reflects reality.
- **`max_multipart_body_parts`** (default `-1` = `max_input_vars + max_file_uploads`, settable per
  directory) is enforced: when it is exceeded, parsing stops with a warning. This is new in 8.0.24
  and 8.0.26 and stock behaviour in 8.0.28. Multipart part headers other than
  `Content-Disposition` / `Content-Type` are ignored, as are duplicates. On 8.0.24 and 8.0.26 the
  "Maximum number of allowable file uploads has been exceeded" warning is now emitted only once
  (`e45850c1`).
- **`X-Powered-By: php-c-mnx`** replaces `X-Powered-By: PHP/8.0.x`. With `ServerTokens Full`, the
  `Server` header reads `Apache/2.4.67 (Debian) php-c-mnx`.
- **`max_execution_time` behaves as in stock 8.0** (regular fatal error, shutdown functions run).
  The timeout signal handler only sets flags, and the error is raised at the next opcode boundary,
  not inside the signal handler. The 8.0 patch does not change this path, and neither does the
  upstream 7.4 patch.
- **No per-request process recycling.** There is no equivalent of FPM's `pm.max_requests = 1`: the
  official recipe's Apache configuration is unchanged (`MaxConnectionsPerChild` stays at Debian's
  default of `0`). Set it in your own image if you want per-request recycling.

Other fatal errors still unwind with `longjmp()`. This is a mitigation, not a complete fix.

## Tests

```bash
sh test/run.sh php:8.0.28-apache-cve
# compare with the official image:
NET=aptest80o CT=ap80o sh test/run.sh php:8.0.28-apache
```

The script runs Apache on a private Docker network (`aptest80` / container `ap80` by default, no
published ports) and drives it over HTTP from a `curlimages/curl` helper container
(`test/tests.sh`). Per-directory settings come from `.htaccess` files in `test/www/up/` and
`test/www/mp/`. `test/servertokens-full.conf` is mounted to make the PHP `Server` token visible;
scenario 8 runs a second container without it. Scenario 9 checks the CLI.

Results were identical for all three patched images, apart from the version numbers:

| Test | Official `php:8.0.24-apache` | Official `php:8.0.28-apache` | Patched 8.0.24 / 8.0.26 / 8.0.28 |
|---|---|---|---|
| Defaults | `memory_limit=128M`, `upload_progress.enabled=1`, no `max_multipart_body_parts` | `memory_limit=128M`, `upload_progress.enabled=1`, `max_multipart_body_parts=-1` | `memory_limit=-1`, `upload_progress.enabled=0`, `max_multipart_body_parts=-1` |
| `X-Powered-By` | `PHP/8.0.24` | `PHP/8.0.28` | `php-c-mnx` |
| `Server` (`ServerTokens Full`) | `Apache/2.4.54 (Debian) PHP/8.0.24` | `Apache/2.4.56 (Debian) PHP/8.0.28` | `Apache/2.4.67 (Debian) php-c-mnx` |
| `Server` (image default) | `Apache/2.4.54 (Debian)` | `Apache/2.4.56 (Debian)` | `Apache/2.4.67 (Debian)` |
| Header lines containing `PHP/<digit>` (Full / default) | 2 / 1 | 2 / 1 | 0 / 0 |
| Upload progress re-enabled via `.htaccess`, session cookie, `cleanup=0` | `upload_progress_prog` written to the session | `upload_progress_prog` written to the session | nothing written |
| `max_multipart_body_parts=3` via `.htaccess`, 6 parts sent | ignored, all parts parsed | warning "Multipart body parts limit exceeded 3", only the first 3 parts parsed | warning "Multipart body parts limit exceeded 3", only the first 3 parts parsed |
| OOM (`memory_limit=16M`, 64 MB string) | HTTP 200 with fatal error, shutdown function runs | HTTP 200 with fatal error, shutdown function runs | `curl: (52) Empty reply from server`, "Fatal error: Allowed memory size…" in the container log, next requests OK (new child PID) |
| OOM (CLI) | fatal, shutdown function runs, exit 255 | fatal, shutdown function runs, exit 255 | fatal, no shutdown function, exit 1 |
| Timeout (`set_time_limit(1)` + busy loop) | fatal "Maximum execution time of 1 second exceeded", shutdown function runs, next request OK | same | same as official (by design, see above) |
| Nested array input (`a[]=…&b[x][y]=…`, GET and POST) | parsed | parsed | parsed identically (exercises `array_init_singleton`) |
| `PHP_VERSION` / `phpversion()` | `8.0.24` | `8.0.28` | unchanged (`8.0.24` / `8.0.26` / `8.0.28`) |

The PHP `make test` suite has **not** been run.

## License

The patches modify PHP source code and are distributed under the
[PHP License 3.01](https://www.php.net/license/3_01.txt). The Dockerfiles and helper scripts are
derived from [docker-library/php](https://github.com/docker-library/php) (MIT).
