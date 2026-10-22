# PHP 8.3 Apache (mod_php) — php2shell-patched images

> **UNTESTED, UNOFFICIAL, NO WARRANTY.** These images apply the **official php.net fix** for
> php2shell, as committed on the php-src `PHP-8.3` line and shipped in PHP 8.3.36, **backported by
> hand** to an older 8.3 release. The backport has not been reviewed by the PHP project; it has been
> exercised by the official regression tests that come with the fix and by the functional tests in
> [`test/`](test/). PHP 8.3.8 also carries many other known vulnerabilities that later 8.3 releases
> fix (8.3.9 … 8.3.36); they are **not** included here. The real fix is to upgrade to PHP ≥ 8.3.36.

PHP **8.3 Apache (mod_php)** Docker images with the fix for **php2shell** —
[CVE-2026-109618](https://github.com/php/php-src/security/advisories/GHSA-w8hw-w9fx-j79w) and
[CVE-2026-109619](https://github.com/php/php-src/security/advisories/GHSA-6wmf-4rv5-p3rp).
Each one is meant as a drop-in replacement for the corresponding official `php:<version>-apache`
image: downstream Dockerfiles only need to change their `FROM` line.

| Directory | Replaces | Planned image |
|---|---|---|
| [`8.3.8/`](8.3.8/) | `php:8.3.8-apache` (Debian bookworm) | `ghcr.io/manuxio/untested-php2shell-fixed-php-fpm-mod_php:8.3.8-apache` |

There is no `latest` tag. Each directory is a self-contained build context:

```bash
docker build -t php:8.3.8-apache-cve 8.3.8/
```

## Build recipe

The `Dockerfile` is the official [docker-library/php](https://github.com/docker-library/php)
`8.3/bookworm/apache/Dockerfile` (plus helper scripts) from the last commit that pinned that PHP
version, i.e. the recipe the last published official image of that tag was built from:

| Version | Recipe | Commit | Next commit (changes the version) |
|---|---|---|---|
| 8.3.8 | `8.3/bookworm/apache` | `b4f429eb7d631134d72a3c47b4bb4b011477253e` | `21e6a92a` "Update 8.3 to 8.3.9" |

(8.3.8 was introduced by `52062af5` "Update to 8.3.8, 8.2.20, 8.1.29 (security releases)",
6 Jun 2024.) That recipe predates "Enable opcache by default" (2025), so — like the official
`php:8.3.8-apache` image — OPcache is built as a shared extension but **not enabled**.

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
PHP 8.3 release keys (the tarball signature is verified during the build). Because the Debian base
image and packages are today's point release, package versions are newer than in the official
image (e.g. Apache 2.4.68 instead of 2.4.59).

The build does **not** regenerate any scanner/parser: the patch already contains the regenerated
files and lists them last, so they are newer than their `.re`/`.y` sources (see below). This matters
because the recipe has `re2c` (Debian's 3.0) but not `bison`; PHP's build silently skips bison when it
is missing, which would otherwise leave a stale JSON parser.

`docker-php-source extract` (used by `docker-php-ext-*`) still unpacks the **pristine**
tarball; extensions built later compile against the installed, patched headers, which is what
matters for them. Do not rebuild the statically compiled core (e.g. `session`) from that tree.

## Patches

### `php-8.3-cve-2026-109618.patch` — provenance

Source: the **official php.net fix**, "Avoid state corruption via bailout" by Arnaud Le Blanc,
Ilija Tovilo, Jakub Zelenka, Nora Dossche and Nicolas Grekas (Fix GHSA-w8hw-w9fx-j79w /
CVE-2026-109618, GHSA-6wmf-4rv5-p3rp / CVE-2026-109619):

- php-src commit [`3c832b523ee13b1a010177d2ff84aea18be0015e`](https://github.com/php/php-src/commit/3c832b523ee13b1a010177d2ff84aea18be0015e)
  (author date 18 Oct 2026, parent `54b4c1a6`), the commit contained in the **`php-8.3.36`** release
  tag. `https://github.com/php/php-src/commit/3c832b52….patch`, sha256
  `29e6a49afe0be0f1ac371c508966ec2695c0002459df01469e95e94e4281f88a`; a copy is in
  [`upstream/`](upstream/).
- On the public `PHP-8.3` branch the same change arrived as merge
  [`c1a5f468d09fc4afc5d738872d5b1d4e87ff1e39`](https://github.com/php/php-src/commit/c1a5f468d09fc4afc5d738872d5b1d4e87ff1e39)
  "Merge branch 'PHP-8.2' into PHP-8.3" (21 Oct 2026, merging the 8.2 fix `3584a98b`). The full git
  trees of `3c832b52` and `c1a5f468` differ **only in `NEWS`**.

Cross-check against the release tarballs: `php-8.3.35.tar.xz` (sha256
`ff4630fbbbd94359134b7d3c223db59329905bdc4f5a9ef93d257b48e358619a`) plus the commit is identical to
`php-8.3.36.tar.xz` (sha256 `dd54693aa334c5c4d72e9aee96b082c2473750a18a6c1d105789c93a3b1692fd`) in
every file the commit touches; the only other differences between the two tarballs are unrelated
commits (CI, Windows, bundled PCRE2) and files regenerated at release time. Remi's packages were not
needed as a source (for supported branches he ships the php.net release itself).

The upstream fix is the **full fix**, not the "minimal mitigation for EOL versions" used for
PHP ≤ 8.1: ~390 files, ~11 000 added lines (about two thirds of it new `.phpt` tests).

#### Backport to 8.3.8

8.3.8 is 28 releases older than the upstream base. `patch -p1 --fuzz=0` of the upstream commit on
pristine 8.3.8 rejects 31 hunks in 22 source/test files (plus the regenerated date parsers, see
below); everything else applies. Each reject was re-applied by hand to the 8.3.8 code, keeping the
upstream change and **not** importing the intermediate fixes that changed the context:

| File | Why the upstream hunk does not apply | Resolution |
|---|---|---|
| `main/rfc1867.c` (4), `main/php_variables.c` (1) | `isspace((unsigned char)…)` from GHSA-m8rr-4c36-8gq4 (`a3841877`); a comment lost its trailing space later | same hunks on the pristine `isspace(*p)` / comment; the ctype fix is not imported (same as in the 8.1 images) |
| `ext/soap/php_http.c` (3) | 8.3.x size/overflow rewrite of `get_http_body()` | fallible allocations applied to the 8.3.8 code (`zend_string_safe_frealloc(…, true)` / `zend_string_falloc(…, true)`, return `NULL` on failure) |
| `ext/soap/soap.c` (1) | whitespace-only change on a line added by a later fix | dropped |
| `Zend/zend_alloc.c` (1) | `tracked_check_limit()` lacks the later `#if ZEND_MM_STAT` guards (`d11f9717`) | upstream replacement (`zend_mm_check_limit()`, `ZEND_MM_MAX_ALLOCS` helpers, fallible `tracked_malloc()`) applied to the unguarded function |
| `Zend/zend_builtin_functions.c` (1) | named-variadic `#[SensitiveParameter]` redaction in `debug_backtrace_get_args()` is a later fix | upstream OOM handling (`zend_hash_fadd_new()` + `oom:` cleanup, `return true/false`) applied to the 8.3.8 loop; the redaction fix is not imported |
| `Zend/zend_objects.c` (1) | `old_opline_before_exception` initialisation changed later | `if (ZEND_HAS_OOM()) return;` inserted at the same place |
| `Zend/zend_vm_def.h` (1) | 8.3.8 spells the helper call `…, -1, 0, 0)` | upstream `free_unfinished_calls()` + `…, -1, op_num, -1)`; `zend_vm_execute.h` (whose hunks applied) is identical to `zend_vm_gen.php` output |
| `ext/bz2/bz2.c` (1) | `bzcompress()` buffer sizing rewritten later | fallible `zend_string_falloc()` + `RETURN_OOM()` on the 8.3.8 code |
| `ext/gd/libgd/gd.c` (1) | `gdImagePaletteToTrueColor()` uses `gdMalloc()` (GH-17772 `gdCalloc` change is later) | `gdMalloc` → fallible `gdFMalloc` |
| `ext/iconv/iconv.c` (1) | stream filter still uses `goto out_failure` | `!ZEND_HAS_OOM() &&` guard applied there |
| `ext/opcache/ZendAccelerator.h` (1) | `zend_accel_globals` has the older key-buffer layout | `pending_ce_cache` member appended after `_key` |
| `ext/simplexml/simplexml.c` (1) | `getName()` uses `RETURN_STRINGL` (no `_FAST` variant yet) | fallible `zend_string_finit()` + `RETURN_OOM()` |
| `ext/standard/assert.c` (1) | bail-out path restructured later | `if (!EG(exception)) zend_throw_unwind_exit();` |
| `ext/standard/string.c` (1) | `strtr()`: `zend_long dummy;` (later `= 0`) | upstream `strtr_oom` handling applied |
| `ext/xml/xml.c` (1) | `xml_get_ctag()` (the anchor) does not exist yet | `xml_handler_aborted()` inserted before `_xml_startElementHandler()` (its callers' hunks applied) |
| `ext/xmlwriter/php_xmlwriter.c` (1) | uses `buffer->content` (later `xmlBufferContent()`) | fallible `zend_string_finit()` on `buffer->content` |
| `main/streams/memory.c` (1) | no NUL-terminator line (later fix) | fallible `zend_string_ftruncate/frealloc` applied |
| `ext/zend_test/*` (7), `observer_fiber_functions_03.phpt` (1) | test extension grew later (not built in the images) | new test helpers placed next to the 8.3.8 functions; `test_arginfo.h` checked against `gen_stub.php` (stub hash `225d437a…`); only the `memory_limit` line removed from the `.phpt` |

Further edits:

- **`Zend/zend_alloc.c`, tracked allocator** (`USE_TRACKED_ALLOC=1` only): added
  `heap->real_size = heap->size;` in `tracked_malloc/free/realloc`, i.e. php-src
  [`9cacc57350e1`](https://github.com/php/php-src/commit/9cacc57350e1) "Track heap->real_size for
  USE_TRACKED_ALLOC" (June 2025). The fix's new limit check reads `heap->real_size`; without this line
  `memory_limit` would not be enforced in tracked-allocation mode. No effect on the normal allocator.
- Dropped: hunks for three tests that do not exist in 8.3.8 (`ext/bcmath/tests/gh17398.phpt`,
  `ext/standard/tests/GHSA-96wq-48vp-hh57.phpt`, `tests/output/gh15179.phpt`).
- **Generated files**: `ext/date/lib/parse_date.c` and `parse_iso_intervals.c` (committed outputs;
  97 + 11 upstream hunks did not apply because 8.3.8's timelib differs) were **regenerated** from the
  patched `.re` files with **re2c 1.0.3** and **re2c 0.15.3**, the versions that generated the 8.3.8
  files (regenerating the pristine `.re` files reproduces 8.3.8's files except the timestamp line).
  The upstream commit changes `var_unserializer.re`, `url_scanner_ex.re`, `json_scanner.re` and
  `json_parser.y` but not their outputs; the patch adds `var_unserializer.c`, `url_scanner_ex.c`,
  `json_scanner.c` and `json_parser.tab.c` regenerated with **re2c 3.0 and bison 3.8.2** (the versions
  that generated the 8.3.8 tarball; pristine regeneration is byte-identical).

Every line added by the upstream commit was checked to be present in the patched tree, except the
ones listed above as adapted or dropped. The patch file is a git diff against the pristine tarball
(393 files) with the upstream commit message and a provenance note on top; it applies with
`--fuzz=0` and without offsets. sha256
`b2611d6d958b6b6cf08275df6e5bdd6b8764dc92b129e9263da6bbef6ddfaee4`.

What the fix changes (summary of the upstream commit):

| Area | Change |
|---|---|
| Out-of-memory handling | OOM no longer `longjmp()`s out of arbitrary code. Exceeding `memory_limit` (the *soft* limit) records a **delayed** "Allowed memory size … exhausted" error that is raised at the next safe point as an `UnwindExit`; fallible allocations (`emalloc`/`zend_string` `f*` variants, `HASH_NOMEM`, `RETURN_OOM()`) let callers unwind cleanly. Many functions/extensions (string, array, json, pcre, mbstring, iconv, date, session, soap, simplexml, exif, gd, …) were converted. A new **hard limit** (default 2 × `memory_limit`, INI `memory_hard_limit_percent`) is enforced for infallible allocations: crossing it prints "Hard memory limit of N bytes exhausted" to stderr and `_exit(137)`s the process. |
| State reset | Globals that survive a bailout or are touched during startup (`SG(request_info)`, `PG(http_globals)`, `EG(...)` error/exception state, objects store after fast shutdown, …) are reset properly. |
| Request parsing | `rfc1867.c`: only `Content-Disposition`/`Content-Type` part headers kept, duplicates ignored, OOM-safe; superglobal sub-arrays start as 1-slot ("singleton") hash tables. |
| Session upload progress | Runs in an "incomplete classes only" (un)serialization mode — no user code (autoload, `__wakeup`, `__unserialize`, `unserialize_callback_func`) can run before RINIT; `$_SESSION` populated this way is removed afterwards. Upload progress itself still works. |
| OPcache | Class-name CE-cache slots published in shared memory only after `ZCSG(map_ptr_last)`, and discarded if a persist window is left via bailout. |
| Tests | ~270 new/updated `.phpt` tests (`oom_*`, `singleton_array`, `rfc1867_*`, …), plus `zend_test` helpers. |

### `php-8.3-mask-server-signature.patch`

Hides the PHP version in server signatures (`php-c-mnx` = PHP 8.x). Generated against the tree
*after* the CVE patch (it is applied second):

- `main/SAPI.h`: `X-Powered-By: PHP/8.3.x` → `X-Powered-By: php-c-mnx` (all SAPIs, mod_php included)
- `sapi/apache2handler/sapi_apache2.c`: Apache `Server` token `PHP/8.3.x` → `php-c-mnx`
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
  duplicates. `max_multipart_body_parts` behaves as in stock 8.3 (native, CVE-2023-0662).
- `X-Powered-By: php-c-mnx` instead of `X-Powered-By: PHP/8.3.8`; with `ServerTokens Full` the
  `Server` header reads `Apache/2.4.x (Debian) php-c-mnx`.
- New INI setting `memory_hard_limit_percent` (from the upstream fix).
- `max_execution_time` behaves as in stock 8.3 (regular fatal error, shutdown functions run).
- The official Apache configuration is left untouched (`MaxConnectionsPerChild 0`).

## Tests

```bash
sh test/run.sh php:8.3.8-apache-cve
# compare with the official image:
NET=aptest83o CT=ap83o sh test/run.sh php:8.3.8-apache
```

Runs Apache on a private Docker network (`aptest83` / container `ap83` by default, no published
ports) and drives it over HTTP from a `curlimages/curl` helper container (`test/tests.sh`), then runs
a few CLI checks. Per-directory settings come from `.htaccess` files in `test/www/up/` and
`test/www/mp/`; `test/servertokens-full.conf` is mounted to make the PHP `Server` token visible.
Observed results:

| Test | Official `php:8.3.8-apache` | Patched `php:8.3.8-apache-cve` |
|---|---|---|
| Defaults | `memory_limit=128M`, `upload_progress.enabled=1`, `max_multipart_body_parts=-1`, OPcache not enabled | `memory_limit=-1`, `upload_progress.enabled=0`, `max_multipart_body_parts=-1`, OPcache not enabled (as in the recipe) |
| `X-Powered-By` | `PHP/8.3.8` | `php-c-mnx` |
| `Server` (`ServerTokens Full`) | `Apache/2.4.59 (Debian) PHP/8.3.8` | `Apache/2.4.68 (Debian) php-c-mnx` |
| Upload progress re-enabled via `.htaccess`, session cookie, `cleanup=0` | `upload_progress_prog` written to the session | nothing written (pinned off via `php_admin_flag`; the hardened official code path would otherwise record it) |
| `max_multipart_body_parts=3` via `.htaccess`, 6 parts sent | "Multipart body parts limit exceeded 3", first 3 parts parsed, plus "Session cookie cannot be sent" warning | same limit warning and same 3 parts; no session-cookie warning |
| OOM, soft (`memory_limit=16M`, 64 MB `str_repeat()`) | HTTP 200 with fatal error, shutdown function runs | same (fallible allocation → delayed OOM) |
| OOM, hard (`memory_limit=16M`, 36 MB concatenation) | HTTP 200 with fatal error, shutdown function runs | `curl: (52) Empty reply from server`, "Hard memory limit of 33554432 bytes exhausted …" in the container log |
| Next requests after OOM | served | served (replacement children) |
| OOM (CLI) soft / hard | fatal, shutdown function runs, exit 255 / same | fatal, shutdown function runs, exit 255 / "Hard memory limit…", no shutdown function, **exit 137** |
| Timeout (`set_time_limit(1)` + busy loop) | fatal "Maximum execution time of 1 second exceeded", shutdown function runs, next request OK | identical |
| Nested array input (`a[]=…&b[x][y]=…`, GET and POST) | parsed | parsed identically (singleton arrays) |
| OPcache CLI (`opcache.enable_cli=1`, loaded for the test) | works | works (patched persist path) |

Source-level checks of the backport (outside Docker, Debian bookworm, same configure flags plus
`--enable-zend-test=shared`): the build has no compiler warnings, and the **267 `.phpt` tests
added/changed by the upstream fix** give 195 passed, 70 skipped (extensions not built in these
images) and 2 expected failures: `Zend/tests/debug_backtrace_sensitive_named_variadic.phpt` tests the
later named-variadic `#[SensitiveParameter]` fix that is not imported, and
`ext/zend_test/tests/zend_test_handle_post_data.phpt` aborts on a double free inside the test-only
`zend_test` helper because 8.3.8 lacks php-src `c47d357d` "Set SG(rfc1867_uploaded_files) to null
after destroy" (verified: it passes with that one line; the helper is the only caller that destroys
the table twice, and `zend_test` is not part of the images). Regression run of the `Zend/`,
`tests/`, `ext/session`, `ext/standard`, `ext/opcache`, `ext/json`, `ext/spl`, `ext/date`,
`ext/pcre` and `ext/mbstring` suites on a pristine 8.3.8 build and on the patched build: 10 939 /
11 083 passed; the same 5 failures on both (`tests/output/stream_isatty_*`, which need a TTY), plus
`debug_backtrace_sensitive_named_variadic.phpt` on the patched build only (explained above). The full
`make test` suite has not been run.

## License

The patches modify PHP source code and are distributed under the
[PHP License 3.01](https://www.php.net/license/3_01.txt). The Dockerfiles and helper scripts
are derived from [docker-library/php](https://github.com/docker-library/php) (MIT).
