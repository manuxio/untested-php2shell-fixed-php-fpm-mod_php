# PHP 8.4 Apache (mod_php) — php2shell-patched images

> **UNTESTED, UNOFFICIAL, NO WARRANTY.** The fix itself is the **official php.net fix** for
> php2shell, but the *backport* to an older 8.4 patch release was done here and has **not** been
> reviewed by the PHP project. It has only been exercised by the functional tests in
> [`test/`](test/) and by the fix's own upstream `.phpt` tests. PHP 8.4.26 also misses the other
> bug fixes of 8.4.27. **The real fix is upgrading to PHP 8.4.27 or later.**

PHP **8.4 Apache (mod_php)** Docker images with the official fix for **php2shell** —
[CVE-2026-109618](https://github.com/php/php-src/security/advisories/GHSA-w8hw-w9fx-j79w) and
[CVE-2026-109619](https://github.com/php/php-src/security/advisories/GHSA-6wmf-4rv5-p3rp),
backported from the PHP 8.4.27 release. Each one is meant as a drop-in replacement for the
corresponding official `php:<version>-apache` image: downstream Dockerfiles only need to change
their `FROM` line.

| Directory | Replaces | Planned image |
|---|---|---|
| [`8.4.26/`](8.4.26/) | `php:8.4.26-apache` (Debian trixie) | `ghcr.io/manuxio/untested-php2shell-fixed-php-fpm-mod_php:8.4.26-apache` |

There is no `latest` tag. Each directory is a self-contained build context:

```bash
docker build -t php:8.4.26-apache-cve 8.4.26/
```

This is the Apache twin of [`8.4-fpm`](../8.4-fpm/): **same patches, byte for byte** (and the
same `php.ini` mitigation file), built from the matching docker-library Apache recipe.

## Build recipe

The `Dockerfile` (plus helper scripts) is the official
[docker-library/php](https://github.com/docker-library/php) `8.4/trixie/apache/` recipe from the
last commit that shipped that PHP version (the same commit as the FPM twin):

| Version | Recipe | Commit | Next commit (changes the version) |
|---|---|---|---|
| 8.4.26 | `8.4/trixie/apache` | `79320e28b93fdc720d6f07d150709310cf54e757` ("[security] Update to 8.5.11, 8.4.26, 8.2.34 (#1685)", 24 Sep 2026) | `f6048b5f` "[security] Update to 8.5.12, 8.4.27, 8.3.36, 8.2.35" |

`php:8.4.26-apache` is the trixie variant (the first Debian variant of `versions.json`, which gets
the un-suffixed tags). Base image, packages, configure flags (`--with-apxs2`, `--disable-cgi`, …),
helper scripts (`docker-php-*`, `apache2-foreground`), entrypoint, OPcache enabled by default,
Apache configuration (prefork MPM, `docker-php.conf`, log symlinks, envvars rewrite),
`STOPSIGNAL SIGWINCH`, `EXPOSE 80`, `CMD`, GPG keys, keyserver and the official `PHP_SHA256` are
unchanged. The **only** changes are:

- the two patches below, copied to `/usr/src/` and applied with `patch -p1 --fuzz=0` right after
  `docker-php-source extract`, before `./configure` (`patch` is already present through
  `dpkg-dev` from `PHPIZE_DEPS`, so no build dependency was added);
- one `touch` of the four `ext/json` generated files right after patching (as in the FPM twin; see
  *Generated files*);
- `/usr/local/etc/php/conf.d/zz-php2shell-mitigations.ini` and
  `/etc/apache2/conf-enabled/zz-php2shell.conf` (see *Behaviour changes*);
- OCI labels.

No EOL/archive fixups were needed: trixie is live and `keyserver.ubuntu.com` still serves the PHP
release keys. Package drift: none observed — the official `php:8.4.26-apache` image was last
rebuilt on 21 Oct 2026, and its installed package list (`dpkg-query -W`, names and versions) is
identical to this image's (e.g. Apache 2.4.69 in both).

`docker-php-source extract` (used by `docker-php-ext-*`) still unpacks the **pristine**
tarball; extensions built later compile against the installed, patched headers, which is what
matters for them. Do not rebuild the statically compiled core (e.g. `session`) from that tree.

## Patches

Both files are byte-identical to [`8.4-fpm/8.4.26/`](../8.4-fpm/8.4.26/); provenance (php-src
commit `506e87fa7dcd`, the fix commit of PHP 8.4.27), the cherry-pick conflicts and their
resolution, the release-tarball and Remi cross-checks and the summary of what the official fix
changes are documented in [`8.4-fpm/README.md`](../8.4-fpm/README.md).

| File | Source | sha256 |
|---|---|---|
| `php-8.4-cve-2026-109618.patch` | official php.net fix, php-src [`506e87fa7dcd`](https://github.com/php/php-src/commit/506e87fa7dcdd306975e5b8f8265ee03527aacbf) (in `php-8.4.27`), backported to 8.4.26, 406 files | `5972ec64737db50ad6a597cde02290d4ce04b1d091e1bbb1910ad6b5c5ed98cf` |
| `php-8.4-mask-server-signature.patch` | `main/SAPI.h`: `X-Powered-By: PHP/8.4.26` → `X-Powered-By: php-c-mnx`; `sapi/apache2handler/sapi_apache2.c`: Apache `Server` token `PHP/8.4.26` → `php-c-mnx` (only visible with `ServerTokens Full`; the image keeps Debian's default `ServerTokens OS`) | `9eec2ce71f1a9de5e0bd4cca42fbde68a8d4914462a8e5dc6cb3368d849398c1` |

Both apply with `patch -p1 --fuzz=0` and no offsets. `phpversion()`, `PHP_VERSION` and `php -v` are
unchanged; `expose_php = Off` still removes the header entirely.

### Generated files

The fix changes `ext/json/json_parser.y`, `ext/json/json_scanner.re`,
`ext/standard/var_unserializer.re` and `ext/standard/url_scanner_ex.re`; **bison is not installed**
in the image. The patch therefore also contains `json_parser.tab.c`, `json_scanner.c`,
`var_unserializer.c` and `url_scanner_ex.c` regenerated with the generators of the php-8.4.26
tarball (bison 3.8.2, re2c 4.5.1; byte-identical to the official php-8.4.27 tarball's), listed last
in the patch so their mtimes are newer than the sources. The Dockerfile additionally `touch`es the
four `ext/json` outputs, exactly like the FPM twin, because the json rule also depends on two
headers the fix does not change (otherwise `make` would re-run Debian's re2c on `json_scanner.re`).
Verified in the build log: the patches apply with no offsets or fuzz (406 + 2 files) and `make`
runs neither re2c nor bison.

## Behaviour changes

- **`memory_limit = -1` by default** (`conf.d/zz-php2shell-mitigations.ini`): there is no PHP-level
  memory cap (and therefore no hard limit either) unless you set one. Downstream images can override
  it with their own ini file, `php_admin_value` or `.htaccess`; container memory limits still apply.
- With a `memory_limit` set: exceeding it no longer `longjmp()`s out of the allocator. The usual
  "Allowed memory size … exhausted" fatal error is raised (possibly a few opcodes later, at the next
  VM interrupt check), the request unwinds cleanly, **shutdown functions run** and the response is
  sent (HTTP 200 with the error, as before); the Apache child survives. Only an **infallible**
  allocation that would cross the new **hard limit** (2 × `memory_limit`, or +1 GB above 1 GB; INI
  `memory_hard_limit_percent`; e.g. a big string concatenation) **terminates the Apache child
  process** with exit status 137: no shutdown functions, no output, "Hard memory limit of N bytes
  exhausted" goes to stderr (container log), the client gets an empty reply; prefork replaces the
  child. CLI: exit status 255 (soft) / 137 (hard).
- `session.upload_progress.enabled = 0` by default (ini file above). **The official fix does not
  force upload progress off**, it hardens it (no user code, incomplete classes only). This image
  therefore also pins it at the Apache level
  (`php_admin_flag session.upload_progress.enabled off` in `conf-enabled/zz-php2shell.conf`),
  so neither `.htaccess` nor `php_value` can re-enable it. Remove that file downstream if you
  need the (hardened) feature back. (The comment lines inside the `.ini` are copied verbatim from
  the FPM twin and mention the FPM pool pin; on this image the pin is the Apache file.)
- Multipart part headers other than `Content-Disposition` / `Content-Type` are ignored, as are
  duplicates. `max_multipart_body_parts` behaves as in stock 8.4 (native, CVE-2023-0662).
- `X-Powered-By: php-c-mnx` instead of `X-Powered-By: PHP/8.4.26`; with `ServerTokens Full` the
  `Server` header reads `Apache/2.4.x (Debian) php-c-mnx`.
- `max_execution_time` behaves as in stock 8.4 (regular fatal error, shutdown functions run).
- The official Apache configuration is left untouched (`MaxConnectionsPerChild 0`).

## Tests

```bash
sh test/run.sh php:8.4.26-apache-cve
# compare with the official image:
NET=aptest84o CT=ap84o sh test/run.sh php:8.4.26-apache
```

Same harness as [`8.3-apache/test`](../8.3-apache/test/) (only the default network/container names
differ). Runs Apache on a private Docker network (`aptest84` / container `ap84` by default, no
published ports) and drives it over HTTP from a `curlimages/curl` helper container
(`test/tests.sh`), then runs a few CLI checks. Per-directory settings come from `.htaccess` files in
`test/www/up/` and `test/www/mp/`; `test/servertokens-full.conf` is mounted to make the PHP `Server`
token visible. Observed results:

| Test | Official `php:8.4.26-apache` | Patched `php:8.4.26-apache-cve` |
|---|---|---|
| Defaults | `memory_limit=128M`, `upload_progress.enabled=1`, `max_multipart_body_parts=-1`, OPcache active | `memory_limit=-1`, `upload_progress.enabled=0`, `max_multipart_body_parts=-1`, OPcache active |
| `X-Powered-By` | `PHP/8.4.26` | `php-c-mnx` |
| `Server` (`ServerTokens Full`) | `Apache/2.4.69 (Debian) PHP/8.4.26` | `Apache/2.4.69 (Debian) php-c-mnx` |
| Upload progress re-enabled via `.htaccess`, session cookie, `cleanup=0` | `upload_progress_prog` written to the session | nothing written (pinned off via `php_admin_flag`; the hardened official code path would otherwise record it) |
| `max_multipart_body_parts=3` via `.htaccess`, 6 parts sent | "Multipart body parts limit exceeded 3", first 3 parts parsed, plus "Session cookie cannot be sent" warning | same limit warning and same 3 parts; no session-cookie warning |
| OOM, soft (`memory_limit=16M`, 64 MB `str_repeat()`) | HTTP 200 with fatal error, shutdown function runs | same (fallible allocation refused, clean unwind) |
| OOM, hard (`memory_limit=16M`, 36 MB concatenation) | HTTP 200 with fatal error, shutdown function runs | `curl: (52) Empty reply from server`, "Hard memory limit of 33554432 bytes exhausted …" in the container log |
| Next requests after OOM | served | served (remaining / replacement children) |
| OOM (CLI) soft / hard | fatal, shutdown function runs, exit 255 / same | fatal, shutdown function runs, exit 255 / "Hard memory limit…", no shutdown function, **exit 137** |
| Timeout (`set_time_limit(1)` + busy loop) | fatal "Maximum execution time of 1 second exceeded", shutdown function runs, next request OK | identical |
| Nested array input (`a[]=…&b[x][y]=…`, GET and POST) | parsed | parsed identically (singleton arrays) |
| OPcache CLI (`opcache.enable_cli=1`, enabled by the image) | works | works (patched persist path) |

Extra ad-hoc checks on the patched image (not part of the harness): with `memory_limit=16M`, an
8 MB . 8 MB concatenation (between the soft and the hard limit) prints the statement after the
allocation, then the fatal error and the shutdown function (delayed OOM), and the set of prefork
children is unchanged (the child survives); a 12 MB . 12 MB concatenation gives an empty reply, the
serving child disappears from the process list (`_exit(137)`, see the CLI row) and prefork spawns a
replacement; the next requests are served.

The full PHP `make test` suite has **not** been run; see the FPM twin's README for the upstream
`.phpt` runs of this exact patch on this exact tree.

## License

The patches modify PHP source code and are distributed under the
[PHP License 3.01](https://www.php.net/license/3_01.txt). The Dockerfile and helper scripts
are derived from [docker-library/php](https://github.com/docker-library/php) (MIT).
