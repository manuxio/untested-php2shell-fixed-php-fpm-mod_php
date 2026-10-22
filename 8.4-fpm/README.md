# PHP 8.4 FPM — php2shell-patched images

> **UNTESTED, UNOFFICIAL, NO WARRANTY.** The fix itself is the **official php.net fix** for
> php2shell, but the *backport* to an older 8.4 patch release was done here and has **not** been
> reviewed by the PHP project. It has only been exercised by the functional tests in
> [`test/`](test/) and by the fix's own upstream `.phpt` tests. PHP 8.4.26 also misses the other
> bug fixes of 8.4.27. **The real fix is upgrading to PHP 8.4.27 or later.**

PHP **8.4 FPM** Docker images with the official fix for **php2shell** —
[CVE-2026-109618](https://github.com/php/php-src/security/advisories/GHSA-w8hw-w9fx-j79w) and
[CVE-2026-109619](https://github.com/php/php-src/security/advisories/GHSA-6wmf-4rv5-p3rp),
backported from the PHP 8.4.27 release. Each one is meant as a drop-in replacement for the
corresponding official `php:<version>-fpm` image: downstream Dockerfiles only need to change their
`FROM` line.

| Directory | Replaces | Planned image |
|---|---|---|
| [`8.4.26/`](8.4.26/) | `php:8.4.26-fpm` (Debian trixie) | `ghcr.io/manuxio/untested-php2shell-fixed-php-fpm-mod_php:8.4.26-fpm` |

There is no `latest` tag. Each directory is a self-contained build context:

```bash
docker build -t php:8.4.26-fpm-cve 8.4.26/
```

## Build recipe

The `Dockerfile` (plus helper scripts) is the official
[docker-library/php](https://github.com/docker-library/php) `8.4/trixie/fpm/` recipe from the last
commit that shipped that PHP version:

| Version | Recipe | Commit | Next commit (changes the version) |
|---|---|---|---|
| 8.4.26 | `8.4/trixie/fpm` | `79320e28b93fdc720d6f07d150709310cf54e757` ("[security] Update to 8.5.11, 8.4.26, 8.2.34 (#1685)", 24 Sep 2026) | `f6048b5f` "[security] Update to 8.5.12, 8.4.27, 8.3.36, 8.2.35" |

`php:8.4.26-fpm` is the trixie variant (the first Debian variant of `versions.json`, which gets the
un-suffixed tags). Base image, packages, configure flags, helper scripts (`docker-php-*`),
entrypoint, OPcache enabled by default, FPM configuration (`docker.conf`, `zz-docker.conf`,
`docker-fpm.ini`), `STOPSIGNAL SIGQUIT`, `EXPOSE 9000`, `CMD`, GPG keys, keyserver and the official
`PHP_SHA256` are unchanged. The **only** changes are:

- the two patches below, copied to `/usr/src/` and applied with `patch -p1 --fuzz=0` right after
  `docker-php-source extract`, before `./configure` (`patch` is already present through
  `dpkg-dev` from `PHPIZE_DEPS`, so no build dependency was added);
- one `touch` of the four `ext/json` generated files right after patching (see *Generated files*);
- `/usr/local/etc/php/conf.d/zz-php2shell-mitigations.ini` and
  `/usr/local/etc/php-fpm.d/zz-php2shell-mitigations.conf` (see *Behaviour changes*);
- OCI labels.

No EOL/archive fixups were needed: trixie is live and `keyserver.ubuntu.com` still serves the PHP
release keys. Package drift: none observed — the official `php:8.4.26-fpm` image was last rebuilt
on 21 Oct 2026 on Debian 13.7, and its installed package list (names and versions) is identical to
this image's.

`docker-php-source extract` (used by `docker-php-ext-*`) still unpacks the **pristine**
tarball; extensions built later compile against the installed, patched headers, which is what
matters for them (verified: `docker-php-ext-install bcmath` works). Do not rebuild the statically
compiled core (e.g. `session`) from that tree.

## Patches

### `php-8.4-cve-2026-109618.patch` — provenance

Source: the **official php.net fix**, php-src commit
[`506e87fa7dcdd306975e5b8f8265ee03527aacbf`](https://github.com/php/php-src/commit/506e87fa7dcdd306975e5b8f8265ee03527aacbf)
"Avoid state corruption via bailout" (Arnaud Le Blanc, co-authored by Ilija Tovilo, Jakub Zelenka,
Nora Dossche, Nicolas Grekas; 18 Oct 2026; "Replace bailout on OOM with UnwindExit / Properly
reset various globals that may be accessed during startup"). It is the fix commit of the
**PHP 8.4.27** release (tag `php-8.4.27` = `00d8bae801541db0d95a698e108bb4b1b273fe6e`; the only
commits after the fix are `2f966f79` "Add NEWS entry", `ed12ac36` CI, `50043816` / `00d8bae8`
version and NEWS bumps). The same change exists on PHP-8.2 as `3584a98bda0f`, merged up into
PHP-8.3 (`c1a5f468`) and PHP-8.4 (`8a94bb38`); the 8.3.36 counterpart is `3c832b52`. GitHub's
`.patch` of the commit: sha256 `c3a5953d1aafcfedf0491bbadaa8e0e9c9fece7c9cc56a7a5f6cc5becb871fec`,
402 files (279 `.phpt`).

Cross-checks:

1. **Release tarball.** `php-8.4.27.tar.xz` from php.net (sha256
   `dcf93923b0e38e0d5252b25b796520b5a47761a08b3488b6d0b5d1115764d3f0`). 8.4.27 is also a regular
   bug-fix release (635 files differ from 8.4.26), so the comparison is against the fix's parent:
   the tag diff `506e87fa^..php-8.4.27` restricted to the commit's files has the **same patch-id**
   as the commit (`cbf06ba54870…`), and those files in the tarball are identical to the tag (except
   `run-tests.php`'s expanded `$Id$`).
2. **Remi's repository.** `rpms/php/php84` commit `60b3de01` "Update to 8.4.27" only touches the
   spec: Remi ships the plain php.net 8.4.27 tarball, no separate php2shell patch.

Backport to 8.4.26 (`git cherry-pick -x 506e87fa` onto tag `php-8.4.26` =
`c31ae58ecbedc7a85dac0eee5a6a88da73543e70`): all files merged automatically except 3 conflicts.
Resolution rule: take the fix's changes, keep 8.4.26's own code for everything that is not part of
the fix:

| File | Conflict | Resolution |
|---|---|---|
| `ext/spl/spl_fixedarray.c` | the fix moves the clone/copy-ctor block of `spl_fixedarray_object_new_ex()` below the parent-class loop and makes it fallible; in 8.4.27's base that block also has an `else { spl_fixedarray_default_ctor(); }` branch from the unrelated GH-23811 fix (`8723e6606a`, not in 8.4.26) | block moved and made fallible exactly as upstream, **without** the GH-23811 `else` branch; the other hunks of the file (fallible `init`/`resize`/`copy_ctor`, `RETURN_OOM()`) merged automatically against 8.4.26's code |
| `ext/zend_test/test_arginfo.h` | generated `Stub hash:` header line (8.4.26's `test.stub.php` differs from 8.4.27's base by the unrelated pcntl test function of `8cb57d2e22`) | hash set to the SHA-1 of the merged `test.stub.php` (`6fa4bb48…`), which is what `build/gen_stub.php` writes; `zend_test` is a test-only extension and is not built in the image |
| `ext/date/lib/parse_date.c` | `/* Generated by re2c 1.0.3 on … */` comment line | 8.4.26's line kept; the fix's code changes in the file merged automatically |

One auto-merged hunk worth noting: in `ext/opcache/ZendAccelerator.c`,
`zend_accel_inheritance_cache_add()` calls the new `zend_accel_pending_ce_cache_commit()` right
after `ZCSG(map_ptr_last) = CG(map_ptr_last)`, as upstream; in 8.4.27's base those lines had been
reordered by the unrelated GH-23637 fix (`873a997d70`), which is not imported. The result has the
same structure as the official 8.3.36 code.

`git range-diff` between the official commit and the backport shows only these differences. The
patch file was then exported against the **pristine php-8.4.26.tar.xz** (sha256
`32a2de53862ad44ed4a5005244ce4f1b50c271e74dced215449a4443b40569f1`): 406 files, applies with
`patch -p1 --fuzz=0` with **no offsets and no fuzz**. File sha256:
`5972ec64737db50ad6a597cde02290d4ce04b1d091e1bbb1910ad6b5c5ed98cf`. Its header keeps the
upstream commit message plus this provenance.

#### Generated files

The fix changes `ext/json/json_parser.y`, `ext/json/json_scanner.re`,
`ext/standard/var_unserializer.re` and `ext/standard/url_scanner_ex.re`. Their bison/re2c outputs are
not in git but are shipped in release tarballs, and **bison is not installed** in the image (a
patched `.y` alone would silently not take effect). The patch therefore also contains
`json_parser.tab.c`, `json_scanner.c`, `var_unserializer.c` and `url_scanner_ex.c`, regenerated
exactly as `scripts/dev/genfiles` does with the generators the php-8.4.26 tarball was built with
(**bison 3.8.2, re2c 4.5.1**, `--no-generation-date`; regenerating the *pristine* 8.4.26 tarball
with them reproduces all six shipped files byte for byte). Cross-check: the four sources **and** the
four generated files are **byte-identical to the official php-8.4.27 tarball's**. Generated files
come last in the patch, so their mtimes are newer than the `.re`/`.y` sources; the Dockerfile
additionally `touch`es the four `ext/json` outputs because the json rule also depends on two headers
the fix does not change (without it, `make` re-runs Debian's re2c 4.1 on `json_scanner.re` —
harmless, but not reproducible).

#### What the official fix changes

| Area | Change |
|---|---|
| OOM handling (`zend_alloc.c`, `zend.c`, `zend_execute*.c`, …) | Exceeding `memory_limit` no longer `longjmp()`s out of the allocator: the error is **delayed** and raised at the next VM interrupt as an `UnwindExit` (like `exit()`), so the request unwinds cleanly. A new **hard limit** (default 2× `memory_limit`, or `memory_limit` + 1 GB above 1 GB; INI `memory_hard_limit_percent`) prints "Hard memory limit … exhausted" to stderr and `_exit(137)`s |
| Fallible allocations | many extensions (json, mbstring, standard, spl, soap, date, gd, intl, xml, zlib, bz2, curl, opcache, …) allocate fallibly and fail with an OOM instead of bailing out mid-update |
| Per-request state | user error/exception handlers and their stacks, `EG(error_handling)`, `EG(objects_store)`, `PG(http_globals)`, `PG(modules_activated)`, session and unserialize state are reset, so nothing leaks into the next request after an aborted one |
| Request startup | multipart: only `Content-Disposition` / `Content-Type` part headers kept, duplicates ignored, OOM-aware parsing (`rfc1867.c`); session upload progress / session start no longer run user code before RINIT |
| OPcache | CE-cache slots published to shared memory only after `ZCSG(map_ptr_last)`, discarded on bailout; JIT (IR) adjustments |
| Tests | ~280 new/updated `.phpt` |

### `php-8.4-mask-server-signature.patch`

Hides the PHP version in server signatures (`php-c-mnx` = PHP 8.x):

- `main/SAPI.h`: `X-Powered-By: PHP/8.4.26` → `X-Powered-By: php-c-mnx` (all SAPIs, FPM included)
- `sapi/apache2handler/sapi_apache2.c`: Apache `Server` token → `php-c-mnx` (not built in this
  image; kept so the patch is shared with the Apache variant)

Applied after the CVE patch (which does not touch `main/SAPI.h` on 8.4), with no offset.
`phpversion()`, `PHP_VERSION` and `php -v` are unchanged. `expose_php = Off` still removes the
header entirely.

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
- **`pm.max_requests = 1`** (`php-fpm.d/zz-php2shell-mitigations.conf`). The official image includes
  `php-fpm.d/*.conf` in alphabetical order: `docker.conf`, `www.conf`, `zz-docker.conf` (which ends
  with an empty `[www]` section), then this file's `[www]` section. Every worker is recycled after a
  single request — belt and braces, so no request can observe state left over by a previous one.
  This costs a fork per request; to change it, override or remove that file in your image.
- **`session.upload_progress.enabled = 0` by default** (ini file), and pinned with
  `php_admin_value[session.upload_progress.enabled] = 0` in the same pool file, so `.user.ini` files
  cannot re-enable it. Note: the official fix does **not** hard-disable upload progress in the
  source (the EOL mitigation did); and FPM applies a web-server-supplied FastCGI `PHP_VALUE` /
  `PHP_ADMIN_VALUE` at master level, bypassing `php_admin_value`, so a web server configured to send
  `PHP_VALUE "session.upload_progress.enabled=1"` still turns it on (that channel is under the web
  server operator's control, not the client's).
- Multipart part headers other than `Content-Disposition` / `Content-Type` are ignored, as are
  duplicates. `max_multipart_body_parts` behaves as in stock 8.4 (native in every 8.4 release; it
  was added for CVE-2023-0662 in 8.0.28 / 8.1.16 / 8.2.3).
- `X-Powered-By: php-c-mnx` instead of `X-Powered-By: PHP/8.4.26`.
- `max_execution_time` behaves as in stock 8.4 (regular fatal error, shutdown functions run).

## Tests

```bash
sh test/run.sh php:8.4.26-fpm-cve
# compare with the official image:
NET=fpmtest84o CT=fpm84o sh test/run.sh php:8.4.26-fpm
```

Runs php-fpm on a private Docker network (`fpmtest84` / container `fpm84` by default, no
published ports), prints the effective pool settings (`php-fpm -tt`), talks FastCGI to it directly
(`test/fcgi.php`, run from a second container of the same image), then runs CLI checks. Observed
results:

| Test | Official `php:8.4.26-fpm` | Patched |
|---|---|---|
| Defaults | `memory_limit=128M`, `upload_progress.enabled=1`, `max_multipart_body_parts=-1`, `pm.max_requests=0` | `memory_limit=-1`, `upload_progress.enabled=0`, `max_multipart_body_parts=-1`, `memory_hard_limit_percent=''` (new INI), `pm.max_requests=1`, `php_admin_value[session.upload_progress.enabled]=0`; OPcache active in both |
| `X-Powered-By` | `PHP/8.4.26` | `php-c-mnx` |
| Upload progress re-enabled per request via FastCGI `PHP_VALUE`, session cookie, `cleanup=0` | `upload_progress_prog` written to the session | **same** (see *Behaviour changes*: FastCGI `PHP_VALUE` bypasses the pool pin, and the official fix keeps the feature) |
| Upload progress re-enabled via `.user.ini` | effective value `'1'` | effective value `'0'` (pool pin) |
| `max_multipart_body_parts=3`, 6 parts sent | warning "Multipart body parts limit exceeded 3", first 3 parts parsed | identical |
| OOM: `memory_limit=16M`, `str_repeat()` of 64 MB | fatal error, shutdown function runs, worker keeps serving | identical output (allocation refused fallibly, clean unwind) |
| OOM, soft limit: 8 MB . 8 MB concatenation | fatal error at the concatenation, shutdown function runs | allocation succeeds, the next statement still runs, then the fatal error, shutdown function runs (delayed OOM) |
| OOM, hard limit: 12 MB . 12 MB concatenation (> 2× limit) | fatal error, shutdown function runs | connection closed without `END_REQUEST`, "Hard memory limit of 33554432 bytes exhausted …" in the FPM log, worker `exited with code 137`, respawned |
| Next requests after OOM (4×) | served, PIDs alternate between the same 2 workers | served, **every PID new** (`pm.max_requests=1`) |
| OOM (CLI), the three scripts above | fatal, shutdown function runs, exit 255 (×3) | fallible / soft: fatal, shutdown function runs, exit 255; hard: "Hard memory limit…", no shutdown function, **exit 137** |
| Timeout (`set_time_limit(1)` + busy loop) | fatal "Maximum execution time of 1 second exceeded", shutdown function runs, next request OK | identical |
| Nested array input (`a[]=…&b[x][y]=…`, GET and POST) | parsed | parsed identically |
| OPcache CLI (`opcache.enable_cli=1`, cache one script) | works | works (patched persist path) |

Upstream regression tests: running every `.phpt` that the fix adds or modifies (279, from the
patched source tree) with each image's `php` binary — **patched: 192 passed, 0 failed** (87 skipped:
need `zend_test`, CGI or other extensions); official `php:8.4.26-fpm`: 167 passed, **25 failed**
(e.g. `Zend/tests/gh11189*.phpt` array state after OOM in `zend_hash_do_resize`,
`oom_after_main_script`, `oom_call_function_003`, `oom_unserialize_016`,
`tests/output/oom_in_internal_output_handler`, `oom_hard_limit_exceeded_during_complilation`,
`ext/date/tests/oom_*`, `ext/mbstring/tests/oom_mb_*`, `ext/hash/tests/hash_pbkdf2_max_length*`,
tokenizer `TOKEN_PARSE` feedback).

The full PHP `make test` suite has **not** been run.

## License

The patches modify PHP source code and are distributed under the
[PHP License 3.01](https://www.php.net/license/3_01.txt). The Dockerfile and helper scripts
are derived from [docker-library/php](https://github.com/docker-library/php) (MIT).
