# PHP 7.4 FPM — `7.4-fpm/`

*Part of [untested-php2shell-fixed-php-fpm-mod_php](https://github.com/manuxio/untested-php2shell-fixed-php-fpm-mod_php).
All paths below are relative to this `7.4-fpm/` directory.*

> **UNTESTED, UNOFFICIAL, NO WARRANTY.** PHP 7.4 has been end-of-life since November 2022.
> These images apply the upstream PHP 7.4 *minimal mitigation* unchanged, but the build itself
> has **not** been reviewed by the PHP project and has only been exercised by the few functional
> tests in [`test/`](test/). PHP 7.4.32 / 7.4.33 have other known, unfixed vulnerabilities.
> Migrate off PHP 7.4.

PHP **7.4.32** and **7.4.33 FPM** Docker images with the upstream PHP 7.4 minimal mitigation for
**php2shell** —
[CVE-2026-109618](https://github.com/php/php-src/security/advisories/GHSA-w8hw-w9fx-j79w) and
[CVE-2026-109619](https://github.com/php/php-src/security/advisories/GHSA-6wmf-4rv5-p3rp).
They are meant as drop-in replacements for the official `php:7.4-fpm` image (and the pinned
`php:7.4.32-fpm`): downstream Dockerfiles only need to change their `FROM` line.

This is the FPM twin of [`7.4-apache/`](../7.4-apache/): same recipe commit, same apt fixups,
same patch files (byte-identical), same mitigation ini. Only the SAPI and the FPM pool override
differ.

## Images

| Version | Directory | Image |
|---|---|---|
| 7.4.33 | [`7.4.33/`](7.4.33/) | `ghcr.io/manuxio/untested-php2shell-fixed-php-fpm-mod_php:7.4.33-fpm` |
| 7.4.32 | [`7.4.32/`](7.4.32/) | `ghcr.io/manuxio/untested-php2shell-fixed-php-fpm-mod_php:7.4.32-fpm` |

7.4.33 is the final PHP 7.4 release. Every version directory is a self-contained build context;
only `PHP_VERSION` / `PHP_URL` / `PHP_SHA256` and the version labels differ between them:

```bash
cd 7.4-fpm
docker build -t php:7.4.33-fpm-cve 7.4.33
docker build -t php:7.4.32-fpm-cve 7.4.32
```

## Build recipe

The recipe is the last official `php:7.4-fpm` (Debian bullseye) Dockerfile from
[docker-library/php](https://github.com/docker-library/php) — `7.4/bullseye/fpm/` at commit
`1361ba95`, the parent of `f2999de8` "Remove PHP 7.4 (EOL 28 November 2022)" — with the same
base image, packages, configure flags (`--enable-fpm --with-fpm-user=www-data
--with-fpm-group=www-data --disable-cgi --with-pear`, ...), helper scripts (`docker-php-*`,
taken verbatim from that commit), entrypoint, FPM configuration (`php-fpm.conf`, `www.conf`,
`docker.conf`, `zz-docker.conf`), `STOPSIGNAL SIGQUIT`, `EXPOSE 9000` and `CMD ["php-fpm"]`.
The official 7.4.32 Dockerfile (`fa38b1c3` "Update 7.4 to 7.4.32") differs from it only in the
three `PHP_*` version lines, so `7.4.32/` uses the same recipe with `PHP_VERSION=7.4.32` and
php.net's SHA256 `323332c9…7864a`. Changes to the official recipe (the same as in
`7.4-apache/`, plus the pool override):

- apt sources point to `archive.debian.org` (`bullseye`, `bullseye-security`, `bullseye-updates`).
  `deb.debian.org` still serves the bullseye indexes but security-pool downloads return 404, so
  builds against the default sources fail. The archive signatures verify with the keys shipped
  in `debian:bullseye-slim`, so **signature checking is kept**. Debian package versions are the
  final bullseye ones, newer than in the November 2022 official image.
- The PHP release keys are still fetched from `keyserver.ubuntu.com` as in the original; the
  tarball is checked against php.net's SHA256 and GPG signature.
- `patch` added to the (auto-purged) build dependencies; the two patches below are applied with
  `patch -p1 --fuzz=0` right after `docker-php-source extract`, before `./configure`. The patch
  files stay in `/usr/src/` for reference.
- Mitigation defaults: `/usr/local/etc/php/conf.d/zz-php2shell-mitigations.ini` and
  `/usr/local/etc/php-fpm.d/zz-php2shell-mitigations.conf` (see *Behaviour changes*).
- OCI labels.

`docker-php-source extract` (used by `docker-php-ext-*`) still unpacks the **pristine** tarball;
extensions built later compile against the installed, patched headers, which is what matters for
them. Do not rebuild the statically compiled core (e.g. `session`) from that tree.

## Patches

Both files are copied **byte for byte** from [`7.4-apache/`](../7.4-apache/), where their
provenance is documented in full, and are identical in both version directories. Both apply to
7.4.32 and 7.4.33 with `--fuzz=0` and zero line offset.

- **`php-7.4-CVE-2026-109618-109619.patch`** — the upstream fix
  [php-src@712e60f9ed](https://github.com/php/php-src/commit/712e60f9edfd03f0960fc4fc3c2c375f42b90aa2)
  ("Avoid state corruption via bailout — Minimal mitigation for EOL version"), which was written
  for PHP 7.4 and is used unchanged (17 files): OOM / allocation overflow → message on stderr +
  `_exit(1)`; concat overflow checks; reset of per-request state and of handlers / exception /
  object store on executor shutdown; `session.upload_progress` forcibly disabled; multipart
  header filtering and the new `max_multipart_body_parts` INI; `array_init_singleton()` for
  superglobal sub-arrays plus the matching `HT_HASH_RESET` fix. See the twin README for the
  comparison with Remi Collet's 7.4 backport (no delta adopted).
- **`php-7.4-mask-server-signature.patch`** — `main/SAPI.h`: `X-Powered-By: PHP/7.4.x` →
  `X-Powered-By: php-b-mnx` (`php-b-mnx` = PHP 7.x). Its `sapi/apache2handler/sapi_apache2.c`
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

- Exceeding `memory_limit`, or any allocation size overflow, **terminates the worker** with
  `_exit(1)`: no shutdown functions, no destructors, the error goes to stderr (the FPM / container
  log, via `catch_workers_output`), not to PHP's `error_log`, and the web server sees the
  FastCGI connection closed without a response (typically a 502). FPM respawns the worker. In the
  CLI, the exit code is 1 instead of 255.
- **`memory_limit = -1` by default** (`conf.d/zz-php2shell-mitigations.ini`): there is no
  PHP-level memory cap unless you set one. Downstream images can override it with their own ini
  file or `php_admin_value`; container memory limits still apply.
- **`pm.max_requests = 1`** (`php-fpm.d/zz-php2shell-mitigations.conf`): every worker is recycled
  after a single request — belt and braces, so no request can ever observe state left over by a
  previous one. This costs a fork per request; to change it, override or remove that file in
  your image.
- `session.upload_progress` never records progress, whatever the INI / `PHP_VALUE` says (the
  default is also set to `0` in the ini file above, so `ini_get()` reflects reality).
- New INI `max_multipart_body_parts` (default `-1` = `max_input_vars + max_file_uploads`); when
  exceeded, parsing stops with a warning. Multipart part headers other than
  `Content-Disposition` / `Content-Type` are ignored, as are duplicates.
- `X-Powered-By: php-b-mnx` instead of `X-Powered-By: PHP/7.4.x`.
- `max_execution_time` is **not** changed by the upstream 7.4 patch and behaves as in stock 7.4:
  the timeout signal handler only sets `EG(timed_out)` / `EG(vm_interrupt)`, and the regular
  fatal error ("Maximum execution time … exceeded") is raised by `zend_timeout()` at the next
  opcode boundary in normal execution context; shutdown functions run and the response is
  delivered normally. The "hard" timeout path already writes to stderr and `_exit()`s.

Other fatal errors still unwind with `longjmp()`; this is a mitigation, not a complete fix.

## Tests

```bash
sh test/run.sh php:7.4.33-fpm-cve
sh test/run.sh php:7.4.32-fpm-cve
# compare with the official image:
NET=fpmtest74o CT=fpm74o sh test/run.sh php:7.4-fpm
```

Runs php-fpm on a private Docker network (`fpmtest74` / container `fpm74` by default, no
published ports) and talks FastCGI to it directly from a second container of the same image
(`test/fcgi.php`, `test/tests.sh`). Per-request INI settings are passed as FastCGI `PHP_VALUE`.
The last step runs the CLI OOM case. Observed results:

| Test | Official `php:7.4-fpm` (7.4.33) | Patched 7.4.33 and 7.4.32 (identical results) |
|---|---|---|
| Defaults | `memory_limit=128M`, `upload_progress.enabled=1`, no `max_multipart_body_parts` | `memory_limit=-1`, `upload_progress.enabled=0`, `max_multipart_body_parts=-1` |
| FPM pool (`php-fpm -tt`) | `pm.max_requests = 0`, `listen = 9000` | `pm.max_requests = 1`, `listen = 9000` |
| `X-Powered-By` | `PHP/7.4.33` | `php-b-mnx` (0 header lines with `PHP/<digit>`) |
| Upload progress re-enabled per request (`PHP_VALUE`), session cookie, `cleanup=0` | `upload_progress_prog` written to the session | nothing written (`SESSION keys:` empty) |
| `max_multipart_body_parts=3` via `PHP_VALUE`, 6 parts sent | unknown INI ("unable to set 'max_multipart_body_parts'"), all parts parsed | warning "Multipart body parts limit exceeded 3", only the first 3 parts parsed (`PHP_SESSION_UPLOAD_PROGRESS,f1,f2`, no file) |
| OOM (`memory_limit=16M`, 64 MB string) | fatal error in the response, shutdown function runs, worker keeps serving | connection closed without `END_REQUEST` (no response), "Fatal error: Allowed memory size…" in the FPM log, `child … exited with code 1`, worker respawned, next requests OK |
| Process recycling | the same two workers serve every request (PIDs 7, 8, 7, …) | a new worker PID for every request (11, 12, 13, …); log shows `exited with code 0` + `started` after each request |
| OOM (CLI) | fatal, shutdown function runs, exit 255 | fatal, no shutdown function, exit 1 |
| Timeout (`set_time_limit(1)` + busy loop) | fatal "Maximum execution time of 1 second exceeded" in the response, shutdown function runs, request completes, next request OK | identical to official: VM-interrupt based fatal at the next opcode, shutdown function runs, request completes normally, the worker exits with code **0** (recycled by `pm.max_requests`, not killed) — unchanged by the patch |
| Nested array input (`a[]=…&b[x][y]=…`, POST) | parsed | parsed identically (exercises `array_init_singleton`) |
| `php -m` | — | identical module list to official; `docker-php-ext-install bcmath` works |

Debian packages come from the final bullseye archive, so they are newer than in the 2022
official image.

The PHP 7.4 `make test` suite has **not** been run.

## License

The patches modify PHP source code and are distributed under the
[PHP License 3.01](https://www.php.net/license/3_01.txt). The Dockerfiles and helper scripts
are derived from [docker-library/php](https://github.com/docker-library/php) (MIT).
