# PHP 8.2 Apache (mod_php) — php2shell-patched images

> **UNTESTED, UNOFFICIAL, NO WARRANTY.** These images apply the **official php.net fix** for
> php2shell, as committed on the php-src `PHP-8.2` branch and shipped in PHP 8.2.35, **backported by
> hand** to an older 8.2 release. The backport has not been reviewed by the PHP project; it has been
> exercised by the official regression tests that come with the fix and by the functional tests in
> [`test/`](test/). PHP 8.2.28 also carries other known vulnerabilities that later 8.2 releases fix
> (8.2.29 … 8.2.35); they are **not** included here. The real fix is to upgrade to PHP ≥ 8.2.35.

PHP **8.2 Apache (mod_php)** Docker images with the fix for **php2shell** —
[CVE-2026-109618](https://github.com/php/php-src/security/advisories/GHSA-w8hw-w9fx-j79w) and
[CVE-2026-109619](https://github.com/php/php-src/security/advisories/GHSA-6wmf-4rv5-p3rp).
Each one is meant as a drop-in replacement for the corresponding official `php:<version>-apache`
image: downstream Dockerfiles only need to change their `FROM` line.

| Directory | Replaces | Planned image |
|---|---|---|
| [`8.2.28/`](8.2.28/) | `php:8.2.28-apache` (Debian bookworm) | `ghcr.io/manuxio/untested-php2shell-fixed-php-fpm-mod_php:8.2.28-apache` |

There is no `latest` tag. Each directory is a self-contained build context:

```bash
docker build -t php:8.2.28-apache-cve 8.2.28/
```

## Build recipe

The `Dockerfile` is the official [docker-library/php](https://github.com/docker-library/php)
`8.2/bookworm/apache/Dockerfile` (plus helper scripts) from the last commit that pinned that PHP
version, i.e. the recipe the last published official image of that tag was built from:

| Version | Recipe | Commit | Next commit (changes the version) |
|---|---|---|---|
| 8.2.28 | `8.2/bookworm/apache` | `f6469f34a0a32c621fc7a2e2eef93fb0b9a36789` | `1d98d9a5` "Update 8.2 to 8.2.29" |

8.2.28 was introduced by `1d34ec5e` (13 Mar 2025); `2a526901` "Enable opcache by default"
(25 Jun 2025) still pinned 8.2.28, so the recipe — like the last official `php:8.2.28-apache`
image — **enables OPcache by default**, and these images keep that.

Base image, packages, configure flags (`--with-apxs2`, `--disable-cgi`, …), helper scripts
(`docker-php-*`, `apache2-foreground`), entrypoint, Apache configuration (prefork MPM,
`docker-php.conf`, log symlinks, envvars rewrite), `STOPSIGNAL`, `EXPOSE 80`, `CMD`, GPG keys,
keyserver and the official `PHP_SHA256` are unchanged. The **only** changes are:

- the two patches below, copied to `/usr/src/` and applied with `patch -p1 --fuzz=0` right after
  `docker-php-source extract`, before `./configure` (`patch` is already present through `dpkg-dev`
  from `PHPIZE_DEPS`, so no build dependency was added);
- `/usr/local/etc/php/conf.d/zz-php2shell-mitigations.ini` (see *Behaviour changes*);
- OCI labels.

No apt/keyserver fixups were needed: bookworm is live and `keyserver.ubuntu.com` still serves the
PHP 8.2 release keys (the tarball signature is verified during the build). Because the Debian base
image and packages are today's point release, package versions are newer than in the official
image (e.g. Apache 2.4.68 instead of 2.4.62).

The build does **not** regenerate any scanner/parser: the patch already contains the regenerated
files and lists them last, so they are newer than their `.re`/`.y` sources (see below). This matters
because the recipe has `re2c` (Debian's 3.0) but not `bison`; PHP's build silently skips bison when it
is missing, which would otherwise leave a stale JSON parser.

`docker-php-source extract` (used by `docker-php-ext-*`) still unpacks the **pristine**
tarball; extensions built later compile against the installed, patched headers, which is what
matters for them. Do not rebuild the statically compiled core (e.g. `session`) from that tree.

## Patches

### `php-8.2-cve-2026-109618.patch` — provenance

Source: the **official php.net fix**, "Avoid state corruption via bailout" by Arnaud Le Blanc,
Ilija Tovilo, Jakub Zelenka, Nora Dossche and Nicolas Grekas (Fix GHSA-w8hw-w9fx-j79w /
CVE-2026-109618, GHSA-6wmf-4rv5-p3rp / CVE-2026-109619):

- php-src commit [`01a40e89fbfc499936e3b05888d8f00bfde886df`](https://github.com/php/php-src/commit/01a40e89fbfc499936e3b05888d8f00bfde886df)
  (author date 18 Oct 2026, parent `512c04e3`), the commit contained in the **`php-8.2.35`** release
  tag. `https://github.com/php/php-src/commit/01a40e89….patch`, sha256
  `23219a0b0d8866fefc2749829a0eb544dd1e840b3d6d9ecf98eff1a47c02dfc4`; a copy is in
  [`upstream/`](upstream/).
- The same change is on the public `PHP-8.2` branch as
  [`3584a98bda0f2c0d367255b046798b0d3a221a19`](https://github.com/php/php-src/commit/3584a98bda0f2c0d367255b046798b0d3a221a19)
  (re-committed 21 Oct 2026 by Ilija Tovilo): **same git tree** (`c5c959a4`) and a byte-identical diff
  body.

Cross-check against the release tarballs: `php-8.2.34.tar.xz` (sha256
`5351330c54de240f54f7527c26ef292e239749e6fe11db0330acb5317e02bb39`) plus the
commit is identical to `php-8.2.35.tar.xz` (sha256
`5737b98601fe5ab1b8c5db0c82ed3158acb9283ed3081ffe2faffb9ac81455e6`) in every file the commit
touches; the only other differences between the two tarballs are unrelated commits (CI, Windows,
bundled PCRE2) and files regenerated at release time. Remi's packages were not needed as a source
(for supported branches he ships the php.net release itself).

The upstream fix is the **full fix**, not the "minimal mitigation for EOL versions" used for
PHP ≤ 8.1: ~390 files, ~11 000 added lines (about two thirds of it new `.phpt` tests).

#### Backport to 8.2.28

`patch -p1 --fuzz=0` of the upstream commit on pristine 8.2.28 leaves 8 rejected hunks in 4 files
(all because of fixes released between 8.2.28 and 8.2.34); everything else applies. Each reject was
re-applied by hand to the 8.2.28 code, keeping the upstream change and **not** importing the
intermediate fix:

| File | Upstream hunk expects | Resolution |
|---|---|---|
| `main/rfc1867.c` (3 hunks), `main/php_variables.c` (1 hunk) | `isspace((unsigned char)*p)` context from GHSA-m8rr-4c36-8gq4 (php-src `a3841877`, 8.2.3x) | same hunks with the pristine `isspace(*p)`; the line the fix moves in `multipart_buffer_headers()` keeps 8.2.28's form. The ctype fix itself is not imported (same as in the 8.1 images). |
| `ext/soap/php_http.c` `get_http_body()` (3 hunks) | 8.2.29's size/overflow rewrite (`size_t http_buf_size`, `ZSTR_MAX_LEN` checks, `zend_string_safe_realloc`) | the upstream fallible-allocation changes applied to 8.2.28's code: `zend_string_safe_frealloc(http_buf, 1, http_buf_size, buf_size, false, true)`, `zend_string_falloc(…, true)` and `zend_string_safe_frealloc(…, 4096, …)`, each returning `NULL` (after releasing the buffer) on failure, as upstream does. |
| `ext/soap/soap.c` (1 hunk) | trailing-whitespace removal on a line (`if (xmlParam != NULL) {`) added by a later fix | dropped (whitespace only; the line does not exist in 8.2.28). |

Further edits:

- **`Zend/zend_alloc.c`, tracked allocator** (`USE_TRACKED_ALLOC=1` only): added
  `heap->real_size = heap->size;` in `tracked_malloc/free/realloc`, i.e. php-src
  [`9cacc57350e1`](https://github.com/php/php-src/commit/9cacc57350e1) "Track heap->real_size for
  USE_TRACKED_ALLOC" (June 2025). The fix's new limit check reads `heap->real_size`; without this line
  `memory_limit` would not be enforced in tracked-allocation mode (caught by the upstream test
  `token_get_all_TOKEN_PARSE_oom_feedback.phpt`). No effect on the normal Zend MM allocator.
- Dropped: the hunk for `ext/standard/tests/GHSA-96wq-48vp-hh57.phpt`, a test that does not exist in
  8.2.28.
- **Generated files**: the upstream commit changes `var_unserializer.re`, `url_scanner_ex.re`,
  `json_scanner.re` and `json_parser.y` but (as usual in php-src) not their outputs. The patch adds
  `ext/standard/var_unserializer.c`, `ext/standard/url_scanner_ex.c`, `ext/json/json_scanner.c` and
  `ext/json/json_parser.tab.c` regenerated with **re2c 2.0.3 and bison 3.7.5** (Debian bullseye), the
  versions that generated the 8.2.28 tarball, with PHP's `scripts/dev/genfiles` flags; regenerating
  the *pristine* sources with them reproduces the tarball's files byte for byte.
  `ext/date/lib/parse_date.c` / `parse_iso_intervals.c` are committed outputs in php-src: the upstream
  hunks applied as-is, and match a re2c 1.0.3 regeneration of the patched `.re` files exactly.
  `Zend/zend_vm_execute.h` / `zend_vm_opcodes.*` match `zend_vm_gen.php` output and
  `ext/zend_test/test_arginfo.h` matches `gen_stub.php` output.

The patch file is a git diff against the pristine tarball (392 files) with the upstream commit
message and a provenance note on top; it applies with `--fuzz=0` and without offsets. sha256
`c63c130bce3544ad53a92e24e904140dddf6554b12319e32fc46331f8f34a0f9`.

What the fix changes (summary of the upstream commit):

| Area | Change |
|---|---|
| Out-of-memory handling | OOM no longer `longjmp()`s out of arbitrary code. Exceeding `memory_limit` (the *soft* limit) records a **delayed** "Allowed memory size … exhausted" error that is raised at the next safe point as an `UnwindExit`; fallible allocations (`emalloc`/`zend_string` `f*` variants, `HASH_NOMEM`, `RETURN_OOM()`) let callers unwind cleanly. Many functions/extensions (string, array, json, pcre, mbstring, iconv, date, session, soap, simplexml, exif, gd, …) were converted. A new **hard limit** (default 2 × `memory_limit`, INI `memory_hard_limit_percent`) is enforced for infallible allocations: crossing it prints "Hard memory limit of N bytes exhausted" to stderr and `_exit(137)`s the process. |
| State reset | Globals that survive a bailout or are touched during startup (`SG(request_info)`, `PG(http_globals)`, `EG(...)` error/exception state, objects store after fast shutdown, …) are reset properly. |
| Request parsing | `rfc1867.c`: only `Content-Disposition`/`Content-Type` part headers kept, duplicates ignored, OOM-safe; superglobal sub-arrays start as 1-slot ("singleton") hash tables. |
| Session upload progress | Runs in an "incomplete classes only" (un)serialization mode — no user code (autoload, `__wakeup`, `__unserialize`, `unserialize_callback_func`) can run before RINIT; `$_SESSION` populated this way is removed afterwards. Upload progress itself still works. |
| OPcache | Class-name CE-cache slots published in shared memory only after `ZCSG(map_ptr_last)`, and discarded if a persist window is left via bailout. |
| Tests | ~270 new/updated `.phpt` tests (`oom_*`, `singleton_array`, `rfc1867_*`, …), plus `zend_test` helpers. |

### `php-8.2-mask-server-signature.patch`

Hides the PHP version in server signatures (`php-c-mnx` = PHP 8.x). Generated against the tree
*after* the CVE patch (it is applied second):

- `main/SAPI.h`: `X-Powered-By: PHP/8.2.x` → `X-Powered-By: php-c-mnx` (all SAPIs, mod_php included)
- `sapi/apache2handler/sapi_apache2.c`: Apache `Server` token `PHP/8.2.x` → `php-c-mnx`
  (only visible with `ServerTokens Full`; the images keep Debian's default `ServerTokens OS`)

`phpversion()`, `PHP_VERSION` and `php -v` are unchanged. `expose_php = Off` still removes the
header entirely.

## Behaviour changes

- **`memory_limit = -1` by default** (`conf.d/zz-php2shell-mitigations.ini`): there is no PHP-level
  memory cap (and therefore no hard limit either) unless you set one. Downstream images can override
  it with their own ini file, `php_admin_value` or `.htaccess`; container memory limits still apply.
- With a `memory_limit` set: exceeding it in a **fallible** allocation (most large allocations in the
  converted functions, e.g. `str_repeat()`, `range()`, `array_fill()`) gives the usual
  "Allowed memory size … exhausted" fatal error, shutdown functions run, and the response is sent
  (HTTP 200 with the error, as before). An **infallible** allocation that would cross the hard limit
  (2 × `memory_limit`; e.g. a big string concatenation) **terminates the Apache child process** with
  exit status 137: no shutdown functions, no output, the message goes to stderr (container log), the
  client gets an empty reply; prefork replaces the child. CLI: exit status 255 (soft) / 137 (hard).
- `session.upload_progress.enabled = 0` by default (ini file above). **Unlike the 8.1 images, the
  official fix does not force upload progress off**, it hardens it (no user code, incomplete
  classes only). This image therefore also pins it at the Apache level
  (`php_admin_flag session.upload_progress.enabled off` in `conf-enabled/zz-php2shell.conf`),
  so neither `.htaccess` nor `php_value` can re-enable it. Remove that file downstream if you
  need the (hardened) feature back.
- Multipart part headers other than `Content-Disposition` / `Content-Type` are ignored, as are
  duplicates. `max_multipart_body_parts` behaves as in stock 8.2 (native since 8.2.3, CVE-2023-0662).
- `X-Powered-By: php-c-mnx` instead of `X-Powered-By: PHP/8.2.28`; with `ServerTokens Full` the
  `Server` header reads `Apache/2.4.x (Debian) php-c-mnx`.
- New INI setting `memory_hard_limit_percent` (from the upstream fix).
- `max_execution_time` behaves as in stock 8.2 (regular fatal error, shutdown functions run).
- The official Apache configuration is left untouched (`MaxConnectionsPerChild 0`).

## Tests

```bash
sh test/run.sh php:8.2.28-apache-cve
# compare with the official image:
NET=aptest82o CT=ap82o sh test/run.sh php:8.2.28-apache
```

Runs Apache on a private Docker network (`aptest82` / container `ap82` by default, no published
ports) and drives it over HTTP from a `curlimages/curl` helper container (`test/tests.sh`), then runs
a few CLI checks. Per-directory settings come from `.htaccess` files in `test/www/up/` and
`test/www/mp/`; `test/servertokens-full.conf` is mounted to make the PHP `Server` token visible.
Observed results:

| Test | Official `php:8.2.28-apache` | Patched `php:8.2.28-apache-cve` |
|---|---|---|
| Defaults | `memory_limit=128M`, `upload_progress.enabled=1`, `max_multipart_body_parts=-1`, OPcache active | `memory_limit=-1`, `upload_progress.enabled=0`, `max_multipart_body_parts=-1`, OPcache active |
| `X-Powered-By` | `PHP/8.2.28` | `php-c-mnx` |
| `Server` (`ServerTokens Full`) | `Apache/2.4.62 (Debian) PHP/8.2.28` | `Apache/2.4.68 (Debian) php-c-mnx` |
| Upload progress re-enabled via `.htaccess`, session cookie, `cleanup=0` | `upload_progress_prog` written to the session | nothing written (pinned off via `php_admin_flag`; the hardened official code path would otherwise record it) |
| `max_multipart_body_parts=3` via `.htaccess`, 6 parts sent | "Multipart body parts limit exceeded 3", first 3 parts parsed, plus "Session cookie cannot be sent" warning | same limit warning and same 3 parts; no session-cookie warning |
| OOM, soft (`memory_limit=16M`, 64 MB `str_repeat()`) | HTTP 200 with fatal error, shutdown function runs | same (fallible allocation → delayed OOM) |
| OOM, hard (`memory_limit=16M`, 36 MB concatenation) | HTTP 200 with fatal error, shutdown function runs | `curl: (52) Empty reply from server`, "Hard memory limit of 33554432 bytes exhausted …" in the container log |
| Next requests after OOM | served | served (replacement children) |
| OOM (CLI) soft / hard | fatal, shutdown function runs, exit 255 / same | fatal, shutdown function runs, exit 255 / "Hard memory limit…", no shutdown function, **exit 137** |
| Timeout (`set_time_limit(1)` + busy loop) | fatal "Maximum execution time of 1 second exceeded", shutdown function runs, next request OK | identical |
| Nested array input (`a[]=…&b[x][y]=…`, GET and POST) | parsed | parsed identically (singleton arrays) |
| OPcache CLI (`opcache.enable_cli=1`, cache one script) | works | works (patched persist path) |

Source-level checks of the backport (outside Docker, Debian bookworm, same configure flags plus
`--enable-zend-test=shared`): the build has no new compiler warnings, and the **265 `.phpt` tests
added/changed by the upstream fix** give 195 passed, 0 failed, 70 skipped (extensions not built in
these images: gd, bz2, intl, soap, …). Regression run of the `Zend/`, `tests/`, `ext/session`,
`ext/standard`, `ext/opcache`, `ext/json`, `ext/spl`, `ext/date`, `ext/pcre` and `ext/mbstring`
suites on a pristine 8.2.28 build and on the patched build: 10 701 / 10 843 passed, and the same 5
failures on both (`tests/output/stream_isatty_*`, which need a TTY) — no test fails only on the
patched build. The full `make test` suite has not been run.

## License

The patches modify PHP source code and are distributed under the
[PHP License 3.01](https://www.php.net/license/3_01.txt). The Dockerfiles and helper scripts
are derived from [docker-library/php](https://github.com/docker-library/php) (MIT).
