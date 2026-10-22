# PHP 8.1 FPM — php2shell-patched images

> **UNTESTED, UNOFFICIAL, NO WARRANTY.** PHP 8.1 has been end-of-life since 31 December 2025 and
> php.net has **not** released a fix for php2shell for this branch. These images apply the
> backport published by Remi Collet's RPM repository (remirepo), lightly refreshed for each
> source tree. Neither the patch adaptation nor these images have been reviewed by the PHP
> project or by Remi Collet; they have only been exercised by the functional tests in
> [`test/`](test/). PHP 8.1.27 and 8.1.28 also carry other known, unfixed vulnerabilities that
> later 8.1 releases (and, for 8.1.34, later remirepo patches) address. Migrate off PHP 8.1.

PHP **8.1 FPM** Docker images with the *minimal mitigation* for **php2shell** —
[CVE-2026-109618](https://github.com/php/php-src/security/advisories/GHSA-w8hw-w9fx-j79w) and
[CVE-2026-109619](https://github.com/php/php-src/security/advisories/GHSA-6wmf-4rv5-p3rp).
Each one is meant as a drop-in replacement for the corresponding official `php:<version>-fpm`
image: downstream Dockerfiles only need to change their `FROM` line. These are the FPM twins of
the [`8.1-apache`](../8.1-apache/) images and use the very same patches and php.ini defaults.

| Directory | Replaces | Planned image |
|---|---|---|
| [`8.1.27/`](8.1.27/) | `php:8.1.27-fpm` (Debian bookworm) | `ghcr.io/manuxio/untested-php2shell-fixed-php-fpm-mod_php:8.1.27-fpm` |
| [`8.1.28/`](8.1.28/) | `php:8.1.28-fpm` (Debian bookworm) | `ghcr.io/manuxio/untested-php2shell-fixed-php-fpm-mod_php:8.1.28-fpm` |
| [`8.1.34/`](8.1.34/) | `php:8.1.34-fpm` (Debian trixie) — **final 8.1 release** (php.net, 18 Dec 2025) | `ghcr.io/manuxio/untested-php2shell-fixed-php-fpm-mod_php:8.1.34-fpm` |

There is no `latest` tag. Each directory is a self-contained build context:

```bash
docker build -t php:8.1.27-fpm-cve 8.1.27/
docker build -t php:8.1.28-fpm-cve 8.1.28/
docker build -t php:8.1.34-fpm-cve 8.1.34/
```

## Build recipes

Each `Dockerfile` is the official [docker-library/php](https://github.com/docker-library/php)
`8.1/<suite>/fpm/Dockerfile` (plus helper scripts) from the same commits as the Apache twins,
i.e. the last commit that pinned that PHP version:

| Version | Recipe | Commit | Next commit (changes the version) |
|---|---|---|---|
| 8.1.27 | `8.1/bookworm/fpm` | `9635283a0b0f63b477f159d5a8ed2c5eebe0b050` | `feeb0150` "Update to 8.1.28 (security release)" |
| 8.1.28 | `8.1/bookworm/fpm` | `bfcdcb3fa5d6e3ba82950fcdd4078d6b6e027fbb` | `52062af5` "Update to 8.3.8, 8.2.20, 8.1.29" |
| 8.1.34 | `8.1/trixie/fpm` | `5c037abaf9dc0095e29807c048d9d1b97e6a9716` | `9cf5f245` "Remove EOL 8.1" |

**OPcache:** as in the official recipes, only the 8.1.34 (trixie) recipe enables OPcache by
default (`docker-php-ext-enable opcache`); on 8.1.27 / 8.1.28 it is built but not loaded. These
images keep that difference.

Base image, packages, configure flags (`--enable-fpm`, `--with-fpm-user/group=www-data`,
`--disable-cgi`, …), helper scripts (`docker-php-*`), entrypoint, FPM configuration layout
(`php-fpm.conf`, `www.conf`, `docker.conf`, `zz-docker.conf`, `conf.d/docker-fpm.ini`),
`STOPSIGNAL SIGQUIT`, `EXPOSE 9000`, `CMD`, GPG keys, keyserver and the official `PHP_SHA256`
values are unchanged. The **only** changes are:

- the two patches below, copied to `/usr/src/` and applied with `patch -p1 --fuzz=0` right
  after `docker-php-source extract`, before `./configure` (`patch` is already present through
  `dpkg-dev` from `PHPIZE_DEPS`, so no build dependency was added);
- `/usr/local/etc/php/conf.d/zz-php2shell-mitigations.ini` (same file as the Apache twins);
- `/usr/local/etc/php-fpm.d/zz-php2shell-mitigations.conf` (`pm.max_requests = 1`);
- OCI labels.

No EOL/archive fixups were needed: bookworm and trixie are live, and the original
`keyserver.ubuntu.com` still serves the PHP release keys. Because the Debian base images and
packages are today's point releases, Debian package versions are newer than in the official
images.

`docker-php-source extract` (used by `docker-php-ext-*`) still unpacks the **pristine**
tarball; extensions built later compile against the installed, patched headers, which is what
matters for them. Do not rebuild the statically compiled core (e.g. `session`) from that tree.

## Patches

Both patch files in each directory are **byte-identical** to the ones in the corresponding
[`8.1-apache`](../8.1-apache/) directory; see the [8.1-apache README](../8.1-apache/README.md)
for full provenance and the per-file change table. In short:

- `php-8.1-cve-2026-109618.patch` — Remi Collet's `php81` `Patch214` from
  `php-8.1.34-6.remi` (git `rpms/php/php81` @ `0ae74cf7`), i.e. the upstream "Minimal mitigation
  for EOL version" (Arnaud Le Blanc / Ilija Tovilo, 8.1 counterpart of
  [php-src@712e60f9ed](https://github.com/php/php-src/commit/712e60f9edfd03f0960fc4fc3c2c375f42b90aa2)),
  with three `isspace((unsigned char)…)` context lines in `main/rfc1867.c` reverted to the
  pristine source (Remi's unrelated ctype backport is not imported) and regenerated per version
  so it applies with `--fuzz=0` and no offsets. The file differs per version (line numbers
  only); content is identical.
- `php-8.1-mask-server-signature.patch` — `X-Powered-By: php-c-mnx` (`main/SAPI.h`) and the
  Apache `Server` token (`sapi/apache2handler/sapi_apache2.c`; that hunk applies but the file is
  not compiled in FPM builds). Identical for all three versions.

All 25 files (23 + 2) patch cleanly on every version (no fuzz, no offsets, verified in the build
logs).

## Behaviour changes

- Exceeding `memory_limit`, or any allocation size overflow, **terminates the worker** with
  `_exit(1)`: no shutdown functions, no destructors, no output flush, the error goes to stderr
  (the FPM log), not to PHP's `error_log`, and the client sees the FastCGI connection closed
  without `END_REQUEST` (nginx reports a 502). FPM logs `child N exited with code 1` and
  respawns the worker; subsequent requests are served normally.
- **`memory_limit = -1` by default** (`conf.d/zz-php2shell-mitigations.ini`): there is no
  PHP-level memory cap unless you set one. Downstream images can override it with their own
  ini file or `php_admin_value`; container memory limits still apply.
- **`pm.max_requests = 1`** (`php-fpm.d/zz-php2shell-mitigations.conf`, included after
  `www.conf`, `docker.conf` and `zz-docker.conf` in alphabetical order): every worker is
  recycled after a single request, so no request can observe state left over by a previous
  one. This costs a fork per request; to change it, override or remove that file in your image.
  The OPcache shared memory belongs to the FPM master and survives worker recycling (tested).
- `session.upload_progress` never records progress, whatever the INI, `PHP_VALUE` or
  `.user.ini` says (the default is also set to `0` in the ini file above, so `ini_get()`
  reflects reality unless something re-enables it).
- Multipart part headers other than `Content-Disposition` / `Content-Type` are ignored, as are
  duplicates. `max_multipart_body_parts` behaves as in stock 8.1 (native since 8.1.17).
- `X-Powered-By: php-c-mnx` instead of `X-Powered-By: PHP/8.1.x`.
- `max_execution_time` behaves as in stock 8.1 (regular fatal error, shutdown functions run).

Other fatal errors still unwind with `longjmp()`; this is a mitigation, not a complete fix.

## Tests

```bash
sh test/run.sh php:8.1.27-fpm-cve
sh test/run.sh php:8.1.28-fpm-cve
sh test/run.sh php:8.1.34-fpm-cve
# compare with an official image:
NET=fpmtest81o CT=fpm81o sh test/run.sh php:8.1.34-fpm
```

Runs php-fpm on a private Docker network (`fpmtest81` / container `fpm81` by default, no
published ports) and talks FastCGI to it directly (`test/fcgi.php`, run from a second container
of the same image; it sends `DOCUMENT_ROOT`, without which FPM does not look up `.user.ini`
files). Per-request settings are sent as `PHP_VALUE`; `test/www/ui/.user.ini` re-enables upload
progress per directory. On images that do not enable OPcache (8.1.27, 8.1.28) the OPcache FPM
check is repeated with `php-fpm -d zend_extension=opcache`. Then a few CLI checks.

Observed results (all three patched images behave identically except where noted; the official
images were run with the same harness):

| Test | Official `php:8.1.{27,28,34}-fpm` | Patched |
|---|---|---|
| Defaults | `memory_limit=128M`, `upload_progress.enabled=1`, `max_multipart_body_parts=-1`, `pm.max_requests=0` | `memory_limit=-1`, `upload_progress.enabled=0`, `max_multipart_body_parts=-1`, `pm.max_requests=1` |
| `X-Powered-By` | `PHP/8.1.27` / `PHP/8.1.28` / `PHP/8.1.34` | `php-c-mnx` |
| Upload progress re-enabled per request (`PHP_VALUE`), session cookie, `cleanup=0` | `upload_progress_prog` written to the session | effective value `'1'`, nothing written to the session; fields and file still parsed |
| Upload progress re-enabled via `.user.ini` | `upload_progress_prog` written to the session | effective value `'1'`, nothing written |
| `max_multipart_body_parts=3`, 6 parts sent | warning "Multipart body parts limit exceeded 3", first 3 parts parsed | identical (native 8.1 feature) |
| OOM (`memory_limit=16M`, 64 MB string) in FPM | fatal error page, shutdown function runs, worker keeps serving | connection closed without `END_REQUEST`, "Fatal error: Allowed memory size of 16777216 bytes exhausted…" in the FPM log, `child N exited with code 1`, respawned, next 4 requests OK, each from a new PID |
| OOM (CLI) | fatal, shutdown function runs, exit 255 | fatal on stderr, no shutdown function, exit 1 |
| Timeout (`set_time_limit(1)` + busy loop) | fatal "Maximum execution time of 1 second exceeded", shutdown function runs, next request OK | identical to official |
| Nested array input (`a[]=…&b[x][y]=…`, GET and POST) | parsed | parsed identically (exercises `array_init_singleton`) |
| OPcache in FPM (3 requests to the same script) | 8.1.34: active, script cached, hits; 8.1.27/28: not loaded (works when loaded with `-d zend_extension=opcache`) | same; with `pm.max_requests=1` each request is a new worker PID and still hits the shared cache (also after the OOM worker kill) |
| OPcache CLI (`opcache.enable_cli=1`, cache one script) | works | works (patched persist path; enabled by the image on 8.1.34, loaded for the test on 8.1.27/8.1.28) |

The PHP `make test` suite has **not** been run.

## License

The patches modify PHP source code and are distributed under the
[PHP License 3.01](https://www.php.net/license/3_01.txt). The Dockerfiles and helper scripts
are derived from [docker-library/php](https://github.com/docker-library/php) (MIT).
