# PHP 8.2 FPM — php2shell-patched images

> **UNTESTED, UNOFFICIAL, NO WARRANTY.** These images apply the **official php.net fix** for
> php2shell, as committed on the php-src `PHP-8.2` branch and shipped in PHP 8.2.35, **backported by
> hand** to an older 8.2 release. The backport has not been reviewed by the PHP project; it has been
> exercised by the official regression tests that come with the fix and by the functional tests in
> [`test/`](test/). PHP 8.2.28 also carries other known vulnerabilities that later 8.2 releases fix
> (8.2.29 … 8.2.35); they are **not** included here. The real fix is to upgrade to PHP ≥ 8.2.35.

PHP **8.2 FPM** Docker images with the fix for **php2shell** —
[CVE-2026-109618](https://github.com/php/php-src/security/advisories/GHSA-w8hw-w9fx-j79w) and
[CVE-2026-109619](https://github.com/php/php-src/security/advisories/GHSA-6wmf-4rv5-p3rp).
Each one is meant as a drop-in replacement for the corresponding official `php:<version>-fpm`
image: downstream Dockerfiles only need to change their `FROM` line.

| Directory | Replaces | Planned image |
|---|---|---|
| [`8.2.28/`](8.2.28/) | `php:8.2.28-fpm` (Debian bookworm) | `ghcr.io/manuxio/untested-php2shell-fixed-php-fpm-mod_php:8.2.28-fpm` |

There is no `latest` tag. Each directory is a self-contained build context:

```bash
docker build -t php:8.2.28-fpm-cve 8.2.28/
```

This is the FPM twin of [`8.2-apache`](../8.2-apache/): **same patches, byte for byte** (and the
same `php.ini` mitigation file), built from the matching docker-library FPM recipe.

## Build recipe

The `Dockerfile` is the official [docker-library/php](https://github.com/docker-library/php)
`8.2/bookworm/fpm/Dockerfile` (plus helper scripts) from the last commit that pinned that PHP
version, i.e. the recipe the last published official image of that tag was built from (the same
commit as the Apache twin):

| Version | Recipe | Commit | Next commit (changes the version) |
|---|---|---|---|
| 8.2.28 | `8.2/bookworm/fpm` | `f6469f34a0a32c621fc7a2e2eef93fb0b9a36789` | `1d98d9a5` "Update 8.2 to 8.2.29" |

8.2.28 was introduced by `1d34ec5e` (13 Mar 2025); `2a526901` "Enable opcache by default"
(25 Jun 2025) still pinned 8.2.28, so the recipe — like the last official `php:8.2.28-fpm`
image — **enables OPcache by default**, and these images keep that. `php:8.2.28-fpm` is the
bookworm variant (the first Debian variant of `versions.json` at that commit).

Base image, packages, configure flags (`--enable-fpm`, `--disable-cgi`, …), helper scripts
(`docker-php-*`), entrypoint, FPM configuration (`php-fpm.conf`, `docker.conf`, `zz-docker.conf`,
`docker-fpm.ini`), `STOPSIGNAL SIGQUIT`, `EXPOSE 9000`, `CMD`, GPG keys, keyserver and the official
`PHP_SHA256` are unchanged. The **only** changes are:

- the two patches below, copied to `/usr/src/` and applied with `patch -p1 --fuzz=0` right after
  `docker-php-source extract`, before `./configure` (`patch` is already present through `dpkg-dev`
  from `PHPIZE_DEPS`, so no build dependency was added);
- `/usr/local/etc/php/conf.d/zz-php2shell-mitigations.ini` and
  `/usr/local/etc/php-fpm.d/zz-php2shell-mitigations.conf` (see *Behaviour changes*);
- OCI labels.

No apt/keyserver fixups were needed: bookworm is live and `keyserver.ubuntu.com` still serves the
PHP 8.2 release keys (the tarball signature is verified during the build). Because the Debian base
image and packages are today's point release, package versions are newer than in the official
image (which was last built on 25 Jun 2025).

The build does **not** regenerate any scanner/parser and, like the Apache twin, needs no `touch`:
the patch already contains the regenerated files and lists them last, so they are newer than their
`.re`/`.y` sources (see the Apache twin's README). This matters because the recipe has `re2c`
(Debian's 3.0) but not `bison`; PHP's build silently skips bison when it is missing, which would
otherwise leave a stale JSON parser. Verified in the build log: neither `re2c` nor `bison` is run.

`docker-php-source extract` (used by `docker-php-ext-*`) still unpacks the **pristine**
tarball; extensions built later compile against the installed, patched headers, which is what
matters for them. Do not rebuild the statically compiled core (e.g. `session`) from that tree.

## Patches

Both files are byte-identical to [`8.2-apache/8.2.28/`](../8.2-apache/8.2.28/); provenance,
backport notes (8 rejected upstream hunks re-applied by hand, tracked-allocator line, generated
files regenerated with re2c 2.0.3 / bison 3.7.5) and the summary of what the official fix changes
are documented in [`8.2-apache/README.md`](../8.2-apache/README.md).

| File | Source | sha256 |
|---|---|---|
| `php-8.2-cve-2026-109618.patch` | official php.net fix, php-src [`01a40e89fbfc`](https://github.com/php/php-src/commit/01a40e89fbfc499936e3b05888d8f00bfde886df) (in `php-8.2.35`; same tree as PHP-8.2 `3584a98bda0f`), backported to 8.2.28, 392 files | `c63c130bce3544ad53a92e24e904140dddf6554b12319e32fc46331f8f34a0f9` |
| `php-8.2-mask-server-signature.patch` | `main/SAPI.h`: `X-Powered-By: PHP/8.2.28` → `X-Powered-By: php-c-mnx`; `sapi/apache2handler/sapi_apache2.c` (not built here; kept so the patch is shared with the Apache variant) | `51ff472da90fa5f51aa1db5f451ed48daa1cb2ed014bd96c111702cf99a71be2` |

Both apply with `patch -p1 --fuzz=0` and no offsets. `phpversion()`, `PHP_VERSION` and `php -v` are
unchanged; `expose_php = Off` still removes the header entirely.

## Behaviour changes

- **OOM no longer kills the worker** (unlike the EOL "minimal mitigation" images for PHP ≤ 8.1,
  which `_exit(1)`): with the official fix, exceeding `memory_limit` produces the usual
  "Allowed memory size … exhausted" fatal error, the request unwinds cleanly and **shutdown functions
  run**; the worker survives. The error may surface a few opcodes after the allocation that
  crossed the limit (delayed until the next VM interrupt check). Only the new **hard limit**
  (2× `memory_limit`) terminates the process: "Hard memory limit of N bytes exhausted" on stderr,
  `exit 137`, no shutdown functions, the client gets a closed connection; FPM respawns the worker.
- New INI `memory_hard_limit_percent` (default empty = 200 %, or +1 GB above 1 GB; `>= 100` or `-1`).
- **`memory_limit = -1` by default** (`conf.d/zz-php2shell-mitigations.ini`): no PHP-level memory
  cap (and therefore no hard limit) unless you set one; container memory limits still apply.
- **`pm.max_requests = 1`** (`php-fpm.d/zz-php2shell-mitigations.conf`). The image includes
  `php-fpm.d/*.conf` in alphabetical order: `docker.conf`, `www.conf`, `zz-docker.conf`, then this
  file's `[www]` section. Every worker is recycled after a single request — belt and braces, so no
  request can observe state left over by a previous one. This costs a fork per request; to change
  it, override or remove that file in your image.
- **`session.upload_progress.enabled = 0` by default** (ini file), and pinned with
  `php_admin_value[session.upload_progress.enabled] = 0` in the same pool file, so `.user.ini` files
  cannot re-enable it. Note: the official fix does **not** hard-disable upload progress in the
  source (it hardens it: no user code, incomplete classes only); and FPM applies a
  web-server-supplied FastCGI `PHP_VALUE` / `PHP_ADMIN_VALUE` at master level, bypassing
  `php_admin_value`, so a web server configured to send
  `PHP_VALUE "session.upload_progress.enabled=1"` still turns it on (that channel is under the web
  server operator's control, not the client's). The comment lines inside the two mitigation files
  are copied verbatim from the twins and are less precise than this paragraph.
- Multipart part headers other than `Content-Disposition` / `Content-Type` are ignored, as are
  duplicates. `max_multipart_body_parts` behaves as in stock 8.2 (native since 8.2.3, CVE-2023-0662).
- `X-Powered-By: php-c-mnx` instead of `X-Powered-By: PHP/8.2.28`.
- `max_execution_time` behaves as in stock 8.2 (regular fatal error, shutdown functions run).

## Tests

```bash
sh test/run.sh php:8.2.28-fpm-cve
# compare with the official image:
NET=fpmtest82o CT=fpm82o sh test/run.sh php:8.2.28-fpm
```

Same harness as [`8.3-fpm/test`](../8.3-fpm/test/) (only the default network/container names
differ). Runs php-fpm on a private Docker network (`fpmtest82` / container `fpm82` by default, no
published ports), prints the effective pool settings (`php-fpm -tt`), talks FastCGI to it directly
(`test/fcgi.php`, run from a second container of the same image), then runs CLI checks. Observed
results:

| Test | Official `php:8.2.28-fpm` | Patched `php:8.2.28-fpm-cve` |
|---|---|---|
| Defaults | `memory_limit=128M`, `upload_progress.enabled=1`, `max_multipart_body_parts=-1`, `pm.max_requests=0` | `memory_limit=-1`, `upload_progress.enabled=0`, `max_multipart_body_parts=-1`, `memory_hard_limit_percent=''` (new INI), `pm.max_requests=1`, `php_admin_value[session.upload_progress.enabled]=0`; OPcache active in both |
| `X-Powered-By` | `PHP/8.2.28` | `php-c-mnx` |
| Upload progress re-enabled per request via FastCGI `PHP_VALUE`, session cookie, `cleanup=0` | `upload_progress_prog` written to the session | **same** (see *Behaviour changes*: FastCGI `PHP_VALUE` bypasses the pool pin, and the official fix keeps the feature) |
| Upload progress re-enabled via `.user.ini` | effective value `'1'` | effective value `'0'` (pool pin) |
| `max_multipart_body_parts=3`, 6 parts sent | warning "Multipart body parts limit exceeded 3", first 3 parts parsed | identical |
| OOM: `memory_limit=16M`, `str_repeat()` of 64 MB | fatal error, shutdown function runs, worker keeps serving | identical output (allocation refused fallibly, clean unwind) |
| OOM, soft limit: 8 MB . 8 MB concatenation | fatal error at the concatenation, shutdown function runs | allocation succeeds, the next statement still runs, then the fatal error, shutdown function runs (delayed OOM) |
| OOM, hard limit: 12 MB . 12 MB concatenation (> 2× limit) | fatal error, shutdown function runs | connection closed without `END_REQUEST`, "Hard memory limit of 33554432 bytes exhausted …" in the FPM log, worker `exited with code 137`, respawned |
| Next requests after OOM (4×) | served, PIDs alternate between the same 2 workers | served, **every PID new** (`pm.max_requests=1`) |
| OOM (CLI), the three scripts above | fatal, shutdown function runs, exit 255 (×3) | fallible / soft: fatal, shutdown function runs, exit 255; hard: "Hard memory limit…", no shutdown function, **exit 137** |
| Timeout (`set_time_limit(1)` + busy loop) | fatal "Maximum execution time of 1 second exceeded", shutdown function runs, next request OK | identical |
| Nested array input (`a[]=…&b[x][y]=…`, GET and POST) | parsed | parsed identically (singleton arrays) |
| OPcache CLI (`opcache.enable_cli=1`, cache one script) | works | works (patched persist path) |

The full PHP `make test` suite has **not** been run; see the Apache twin's README for the
source-level `.phpt` runs of this exact patch on this exact tree.

## License

The patches modify PHP source code and are distributed under the
[PHP License 3.01](https://www.php.net/license/3_01.txt). The Dockerfile and helper scripts
are derived from [docker-library/php](https://github.com/docker-library/php) (MIT).
