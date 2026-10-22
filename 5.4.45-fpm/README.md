# PHP 5.4.45 FPM (php2shell-patched)

> **UNTESTED, UNOFFICIAL, NO WARRANTY.** This is a best-effort, hand-made backport for a
> PHP version that has been end-of-life since 2015. It has **not** been reviewed by the PHP
> project and has only been exercised by the few functional tests in [`test/`](test/).
> PHP 5.4.45 has many other known, unfixed vulnerabilities. Migrate off PHP 5.4.

A PHP **5.4.45 FPM** Docker image with an adaptation of the PHP 7.4 *minimal mitigation*
for **php2shell** — [CVE-2026-109618](https://github.com/php/php-src/security/advisories/GHSA-w8hw-w9fx-j79w)
and [CVE-2026-109619](https://github.com/php/php-src/security/advisories/GHSA-6wmf-4rv5-p3rp).

## Image

```bash
docker pull ghcr.io/manuxio/untested-php2shell-fixed-php-fpm-mod_php:5.4.45-fpm
```

The build recipe is the last official `php:5.4-fpm` Dockerfile from
[docker-library/php](https://github.com/docker-library/php) (commit `49a731d3^`, Debian jessie),
with the same configure flags, extensions and `php-fpm.conf`. Changes to that recipe:

- apt sources point to `archive.debian.org` (jessie and jessie/updates). **The archive signing
  keys have expired, so Debian packages are installed without signature verification.**
- GPG key fetched from `keyserver.ubuntu.com` (the SKS pool no longer exists).
- PHP tarball downloaded over HTTPS and checked against php.net's published SHA256 in
  addition to the GPG signature.
- `php-5.4-CVE-2026-109618-109619.patch` applied with `patch --fuzz=0`.
- `php-5.4-mask-server-signature.patch`: the PHP version is masked in server
  signatures — `X-Powered-By: php-a-mnx` instead of `X-Powered-By: PHP/5.4.45`
  (and the Apache `Server` token in apxs2 builds). `phpversion()` / `PHP_VERSION`
  are untouched.
- The recommended php2shell mitigations are baked in as defaults:
  `session.upload_progress.enabled=0` and `memory_limit=-1`
  (`conf.d/zz-php2shell-mitigations.ini`, overridable downstream) and
  `pm.max_requests=1` in `php-fpm.conf`.

Build it yourself:

```bash
docker build -t php:5.4.45-fpm-cve .
```

## What the patch does

The upstream PHP 7.4 patch ([php-src@712e60f9ed](https://github.com/php/php-src/commit/712e60f9edfd03f0960fc4fc3c2c375f42b90aa2))
does not apply to 5.4 (Zend Engine 2.4 vs 3), so it was re-implemented by hand:

| Upstream 7.4 idea | 5.4 port |
|---|---|
| OOM / allocation overflow: print fatal error and `_exit(1)` instead of `zend_error()` + `longjmp()` (`zend_mm_safe_error_ex`) | `zend_mm_safe_error`, all `safe_address` variants, `Balloc()`, string concat overflow, `zend_mm_panic` |
| Reset per-request globals that outlive the request | `SG(request_info)` pointers (plus 5.x-only `post_data` / `raw_post_data`), `PG(http_globals)`, `PG(modules_activated)`, error/exception handlers, `objects_store`, `zend_llist` head/tail |
| Session upload progress forcibly disabled | same |
| Multipart: keep only `Content-Disposition` / `Content-Type`, ignore duplicates, new `max_multipart_body_parts` INI, `size_t` in `substring_conf` | same |
| `array_init_singleton` / `HT_HASH_RESET` | not ported (7.x hash table internals; 5.4 already allocates buckets lazily) |

**Beyond the upstream 7.4 patch:** `max_execution_time` / `max_input_time`. In 5.4 the timeout
fires from a SIGPROF signal handler that calls `zend_error()` and `longjmp()`s out of whatever
code was interrupted (allocator included). The handler now writes the fatal error to stderr
and `_exit(1)`s.

## Behaviour changes

- Exceeding `memory_limit` or `max_execution_time` **terminates the worker**: no shutdown
  functions, the error goes to stderr (the FPM log), not to PHP's `error_log`, and the client
  sees a closed connection. FPM respawns the worker.
- `session.upload_progress` never records progress, whatever `php.ini` says.
- New INI `max_multipart_body_parts` (default `-1` = `max_input_vars + max_file_uploads`).
- Default INI: `session.upload_progress.enabled=0`, `memory_limit=-1` (no PHP memory cap:
  rely on container/cgroup limits; a failed allocation still terminates the worker).
  Override in a later `conf.d` file if you need the old defaults.
- `pm.max_requests=1`: every FPM worker exits after serving one request and is respawned,
  so no request can observe state left behind by a previous one.

Other fatal errors still unwind with `longjmp()`; this is a mitigation, not a complete fix.

## Tests

```bash
sh test/run.sh php:5.4.45-fpm-cve
```

Runs php-fpm and talks FastCGI to it directly (`test/fcgi.php`). Observed results:

| Test | Unpatched 5.4.45 | Patched |
|---|---|---|
| OOM (CLI) | fatal, shutdown function runs, exit 255 | fatal, no shutdown function, exit 1 |
| OOM (FPM) | worker unwinds and keeps serving | worker exits(1), respawned, next request OK |
| Timeout (FPM) | not run (by code: fatal via `longjmp()` from the signal handler) | worker exits(1), respawned, next request OK |
| Upload progress with session cookie | writes `upload_progress_*` to session | nothing written |
| `max_multipart_body_parts=3` | unknown INI, all parts parsed | stops after 3 parts |

The PHP 5.4 `make test` suite has **not** been run.

## License

The patch modifies PHP source code and is distributed under the
[PHP License 3.01](https://www.php.net/license/3_01.txt). The Dockerfile and helper scripts
are derived from [docker-library/php](https://github.com/docker-library/php) (MIT).
