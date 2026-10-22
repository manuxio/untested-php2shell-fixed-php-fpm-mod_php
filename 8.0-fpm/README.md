# PHP 8.0 FPM — `8.0-fpm/`

*Part of [untested-php2shell-fixed-php-fpm-mod_php](https://github.com/manuxio/untested-php2shell-fixed-php-fpm-mod_php).
All paths below are relative to this `8.0-fpm/` directory.*

> **UNTESTED, UNOFFICIAL, NO WARRANTY.** These images apply an unofficial (third-party) backport to a
> PHP branch that has been end-of-life since 26 November 2023. Neither the backport nor these images
> have been reviewed by the PHP project. They have only been exercised by the functional tests in
> [`test/`](test/). PHP 8.0.24, 8.0.26 and 8.0.28 all have other known, unfixed vulnerabilities
> (8.0.24 and 8.0.26 even lack fixes that later 8.0.x releases shipped). Migrate off PHP 8.0.

PHP **8.0.24, 8.0.26 and 8.0.28 FPM** Docker images with the PHP 8.0 *minimal mitigation* for
**php2shell** —
[CVE-2026-109618](https://github.com/php/php-src/security/advisories/GHSA-w8hw-w9fx-j79w) and
[CVE-2026-109619](https://github.com/php/php-src/security/advisories/GHSA-6wmf-4rv5-p3rp).
Each one is meant as a drop-in replacement for the official `php:<version>-fpm` image (or
`php:8.0-fpm`), so downstream Dockerfiles only need to change their `FROM` line.

This is the FPM twin of [`8.0-apache/`](../8.0-apache/): same recipe commit, same apt fixups,
same patch files (byte-identical, same per-version set), same mitigation ini. Only the SAPI and
the FPM pool override differ.

## Images

| Version | Directory | Image |
|---|---|---|
| 8.0.28 | [`8.0.28/`](8.0.28/) | `ghcr.io/manuxio/untested-php2shell-fixed-php-fpm-mod_php:8.0.28-fpm` |
| 8.0.26 | [`8.0.26/`](8.0.26/) | `ghcr.io/manuxio/untested-php2shell-fixed-php-fpm-mod_php:8.0.26-fpm` |
| 8.0.24 | [`8.0.24/`](8.0.24/) | `ghcr.io/manuxio/untested-php2shell-fixed-php-fpm-mod_php:8.0.24-fpm` |

Every version directory is a self-contained build context:

```bash
cd 8.0-fpm
docker build -t php:8.0.28-fpm-cve 8.0.28
docker build -t php:8.0.26-fpm-cve 8.0.26
docker build -t php:8.0.24-fpm-cve 8.0.24
```

## Build recipe

All three images use the last official `php:8.0-fpm` Dockerfile from
[docker-library/php](https://github.com/docker-library/php): `8.0/bullseye/fpm/` at commit
`df4636ca`, the parent of `4d3ed4a9` "Remove PHP 8.0 (EOL 26 November 2023)". That recipe built
8.0.30. These images keep its Debian bullseye base image, packages, configure flags
(`--enable-fpm --with-fpm-user=www-data --with-fpm-group=www-data --disable-cgi --with-pear`, …),
helper scripts (`docker-php-*`, taken verbatim from that commit), entrypoint, FPM configuration
(`php-fpm.conf`, `www.conf`, `docker.conf`, `zz-docker.conf`, `conf.d/docker-fpm.ini`),
`STOPSIGNAL SIGQUIT`, `EXPOSE 9000` and `CMD ["php-fpm"]`.

The official 8.0.24 and 8.0.26 images were built in 2022 from earlier revisions of that recipe;
these images use the final revision for all three versions, exactly as `8.0-apache/` does. The
changes to that recipe are:

- **`PHP_VERSION`, `PHP_URL` and `PHP_SHA256`** are pinned per directory (php.net's official
  SHA256 values; the tarballs are still verified against php.net's GPG signatures using the
  recipe's 8.0 release-manager keys and `keyserver.ubuntu.com`).
- **apt sources point to `archive.debian.org`** (`bullseye`, `bullseye-security`,
  `bullseye-updates`). deb.debian.org now publishes `bullseye-security` indexes whose pool files
  return 404. The archive signatures still verify with the keys shipped in
  `debian:bullseye-slim`, so **signature checking is kept**. Debian package versions are the final
  bullseye ones, newer than in the original images.
- **`patch` is added** to the (auto-purged) build dependencies. The patches below are applied
  with `patch -p1 --fuzz=0` right after `docker-php-source extract` and before `./configure`.
  The patch files stay in `/usr/src/` for reference.
- **Mitigation defaults**: `/usr/local/etc/php/conf.d/zz-php2shell-mitigations.ini` and
  `/usr/local/etc/php-fpm.d/zz-php2shell-mitigations.conf` (see *Behaviour changes*).
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

All files are copied **byte for byte** from [`8.0-apache/`](../8.0-apache/), where their
provenance is documented in full (including Remi Collet's original file and the two-line
pre-image adjustment). They are applied in the order shown in the table, and all apply with
`--fuzz=0` (some hunks at a line offset, exactly as in the Apache build).

- **`php-8.0-cve-2026-109618.patch`** — Remi Collet's PHP 8.0 backport of the upstream
  *"Avoid state corruption via bailout. Minimal mitigation for EOL version"* (remirepo `php80`
  8.0.30-21, `Patch238`, git `838396b4`), with only two `rfc1867.c` pre-image lines changed back to
  the pristine source so it applies to php.net tarballs. 17 files: OOM / allocation overflow →
  message on stderr + `_exit(1)`; concat overflow checks; reset of per-request state and of
  handlers / exception / object store on executor shutdown; `session.upload_progress` forcibly
  disabled; multipart header filtering; `array_init_singleton()` for superglobal sub-arrays plus
  the `HT_HASH_RESET` small-table fix.
- **`php-8.0-cve-2023-0662.patch`** (8.0.24 and 8.0.26 only) — php-src `e45850c1` + `716de0cf`
  from the `PHP-8.0` branch (shipped in 8.0.28): introduces `max_multipart_body_parts`, on which
  the php2shell mitigation relies. FPM test-suite files of `716de0cf` are omitted.
- **`php-8.0-mask-server-signature.patch`** — `main/SAPI.h`: `X-Powered-By: PHP/8.0.x` →
  `X-Powered-By: php-c-mnx` (`php-c-mnx` = PHP 8.x). Its `sapi/apache2handler/sapi_apache2.c`
  hunk (Apache `Server` token) applies but is not compiled in this image; it is kept so the file
  stays shared with the Apache variant. `phpversion()`, `PHP_VERSION` and `php -v` are
  unchanged; `expose_php = Off` still removes the header entirely.

## FPM configuration

The official image's FPM pool configuration is kept as is: `php-fpm.conf` includes
`etc/php-fpm.d/*.conf` in alphabetical order, i.e. `docker.conf`, `www.conf`, `zz-docker.conf`.
This image adds `php-fpm.d/zz-php2shell-mitigations.conf`, which sorts after `zz-docker.conf`
and therefore wins for the `[www]` pool:

```ini
[www]
pm.max_requests = 1
```

`php-fpm -tt` in the image reports `pm.max_requests = 1` and `listen = 9000`.

## Behaviour changes

- **OOM kills the worker.** Exceeding `memory_limit`, or any allocation size overflow,
  terminates the worker with `_exit(1)`: no shutdown functions or destructors run, the error goes
  to stderr (the FPM / container log, via `catch_workers_output`), not to PHP's `error_log`, and
  the web server sees the FastCGI connection closed without a response (typically a 502). FPM
  respawns the worker. In the CLI, the exit code is 1 instead of 255.
- **`memory_limit = -1` by default** (`conf.d/zz-php2shell-mitigations.ini`), so there is no
  PHP-level memory cap unless you set one. Downstream images can override it with their own ini
  file or `php_admin_value`. Container memory limits still apply.
- **`pm.max_requests = 1`** (`php-fpm.d/zz-php2shell-mitigations.conf`): every worker is recycled
  after a single request — belt and braces, so no request can ever observe state left over by a
  previous one. This costs a fork per request; to change it, override or remove that file in
  your image.
- **`session.upload_progress` never records progress**, whatever the INI or `PHP_VALUE` says. The
  default is also set to `0` in the ini file above, so `ini_get()` reflects reality.
- **`max_multipart_body_parts`** (default `-1` = `max_input_vars + max_file_uploads`) is
  enforced: when it is exceeded, parsing stops with a warning. This is new in 8.0.24 and 8.0.26
  and stock behaviour in 8.0.28. Multipart part headers other than `Content-Disposition` /
  `Content-Type` are ignored, as are duplicates. On 8.0.24 and 8.0.26 the "Maximum number of
  allowable file uploads has been exceeded" warning is now emitted only once (`e45850c1`).
- **`X-Powered-By: php-c-mnx`** replaces `X-Powered-By: PHP/8.0.x`.
- **`max_execution_time` behaves as in stock 8.0** (regular fatal error, shutdown functions run,
  response delivered). The timeout signal handler only sets `EG(timed_out)` /
  `EG(vm_interrupt)`, and the error is raised by `zend_timeout()` at the next opcode boundary,
  not inside the signal handler. The 8.0 patch does not change this path, and neither does the
  upstream 7.4 patch. The "hard" timeout path already writes to stderr and `_exit()`s.

Other fatal errors still unwind with `longjmp()`. This is a mitigation, not a complete fix.

## Tests

```bash
sh test/run.sh php:8.0.28-fpm-cve
# compare with the official image:
NET=fpmtest80o CT=fpm80o sh test/run.sh php:8.0.28-fpm
```

Runs php-fpm on a private Docker network (`fpmtest80` / container `fpm80` by default, no
published ports) and talks FastCGI to it directly from a second container of the same image
(`test/fcgi.php`, `test/tests.sh`). Per-request INI settings are passed as FastCGI `PHP_VALUE`.
The last step runs the CLI OOM case. Observed results:

Results were identical for all three patched images, apart from version numbers and PIDs:

| Test | Official `php:8.0.24-fpm` | Official `php:8.0.28-fpm` | Patched 8.0.24 / 8.0.26 / 8.0.28 |
|---|---|---|---|
| Defaults | `memory_limit=128M`, `upload_progress.enabled=1`, no `max_multipart_body_parts` | `memory_limit=128M`, `upload_progress.enabled=1`, `max_multipart_body_parts=-1` | `memory_limit=-1`, `upload_progress.enabled=0`, `max_multipart_body_parts=-1` |
| FPM pool (`php-fpm -tt`) | `pm.max_requests = 0`, `listen = 9000` | same | `pm.max_requests = 1`, `listen = 9000` |
| `X-Powered-By` | `PHP/8.0.24` | `PHP/8.0.28` | `php-c-mnx` (0 header lines with `PHP/<digit>`) |
| Upload progress re-enabled per request (`PHP_VALUE`), session cookie, `cleanup=0` | `upload_progress_prog` written to the session | `upload_progress_prog` written to the session | nothing written (`SESSION keys:` empty) |
| `max_multipart_body_parts=3` via `PHP_VALUE`, 6 parts sent | unknown INI ("unable to set 'max_multipart_body_parts'"), all parts parsed | warning "Multipart body parts limit exceeded 3", only the first 3 parts parsed | warning "Multipart body parts limit exceeded 3", only the first 3 parts parsed (`PHP_SESSION_UPLOAD_PROGRESS,f1,f2`, no file) |
| OOM (`memory_limit=16M`, 64 MB string) | fatal error in the response, shutdown function runs, worker keeps serving | same | connection closed without `END_REQUEST` (no response), "Fatal error: Allowed memory size…" in the FPM log, `child … exited with code 1`, worker respawned, next requests OK |
| Process recycling | the same two workers serve every request (PIDs 7, 8, 7, …) | same | a new worker PID for every request (10, 11, 12, …); log shows `exited with code 0` + `started` after each request |
| OOM (CLI) | fatal, shutdown function runs, exit 255 | same | fatal, no shutdown function, exit 1 |
| Timeout (`set_time_limit(1)` + busy loop) | fatal "Maximum execution time of 1 second exceeded" in the response, shutdown function runs, request completes, next request OK | same | identical to official: VM-interrupt based fatal at the next opcode, shutdown function runs, request completes normally, the worker exits with code **0** (recycled by `pm.max_requests`, not killed) — unchanged by the patch |
| Nested array input (`a[]=…&b[x][y]=…`, POST) | parsed | parsed | parsed identically (exercises `array_init_singleton`) |
| `php -m` | — | — | identical module list to official (8.0.24, 8.0.28); `docker-php-ext-install bcmath` works |

Debian packages come from the final bullseye archive, so they are newer than in the original
official images.

The PHP `make test` suite has **not** been run.

## License

The patches modify PHP source code and are distributed under the
[PHP License 3.01](https://www.php.net/license/3_01.txt). The Dockerfiles and helper scripts are
derived from [docker-library/php](https://github.com/docker-library/php) (MIT).
