# PHP 5.4.45 Apache/mod_php (php2shell-patched)

> **UNTESTED, UNOFFICIAL, NO WARRANTY.** This is a best-effort, hand-made backport for a
> PHP version that has been end-of-life since 2015. It has **not** been reviewed by the PHP
> project and has only been exercised by the few functional tests in [`test/`](test/).
> PHP 5.4.45 has many other known, unfixed vulnerabilities. Migrate off PHP 5.4.

A PHP **5.4.45 Apache/mod_php** Docker image with an adaptation of the PHP 7.4 *minimal mitigation*
for **php2shell** — [CVE-2026-109618](https://github.com/php/php-src/security/advisories/GHSA-w8hw-w9fx-j79w)
and [CVE-2026-109619](https://github.com/php/php-src/security/advisories/GHSA-6wmf-4rv5-p3rp).
It is meant as a drop-in replacement for the official `php:5.4-apache` image: switch the
`FROM` line, nothing else.

## Image

```bash
docker pull ghcr.io/manuxio/untested-php2shell-fixed-php:5.4.45-apache
```

The build recipe is the last official `php:5.4-apache` Dockerfile from
[docker-library/php](https://github.com/docker-library/php) (commit `49a731d3^`, Debian jessie),
with the same apt packages, configure flags (`--with-apxs2`), extensions, `apache2.conf`,
`apache2-foreground`, `docker-php-ext-*` helpers, `WORKDIR`, `EXPOSE 80` and `CMD`.
Changes to that recipe:

- apt sources point to `archive.debian.org` (jessie and jessie/updates). **The archive signing
  keys have expired, so Debian packages are installed without signature verification.**
- GPG key fetched from `keyserver.ubuntu.com` (the SKS pool no longer exists).
- PHP tarball downloaded over HTTPS and checked against php.net's published SHA256 in
  addition to the GPG signature.
- `php-5.4-CVE-2026-109618-109619.patch` applied with `patch --fuzz=0` (`patch` added to the
  build deps, purged afterwards).
- `php-5.4-mask-server-signature.patch` applied right after it (also `--fuzz=0`): the PHP
  version is masked in server signatures — `X-Powered-By: php-a-mnx` instead of
  `X-Powered-By: PHP/5.4.45`, and the Apache `Server` token says `php-a-mnx` instead of
  `PHP/5.4.45` (e.g. `Server: Apache/2.4.10 (Debian) php-a-mnx`). `phpversion()` /
  `PHP_VERSION` are untouched; `expose_php = Off` still removes both.
- `zz-php2shell-mitigations.ini` added to `/usr/local/etc/php/conf.d/` (see *Behaviour changes*).

Build it yourself:

```bash
docker build -t php:5.4.45-apache-cve .
```

## What the patch does

The upstream PHP 7.4 patch ([php-src@712e60f9ed](https://github.com/php/php-src/commit/712e60f9edfd03f0960fc4fc3c2c375f42b90aa2))
does not apply to 5.4 (Zend Engine 2.4 vs 3), so it was re-implemented by hand. The patch is
SAPI-independent and identical to the one in the
[FPM variant](https://github.com/manuxio/untested-php2shell-fixed-php).

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

- Exceeding `memory_limit` or `max_execution_time` **terminates the Apache prefork child**
  that runs mod_php: no shutdown functions, the error goes to stderr (Apache's `ErrorLog`,
  i.e. `docker logs`), not to PHP's `error_log`, and the client gets an aborted response
  (connection closed with no HTTP response, e.g. curl "Empty reply from server"; a reverse
  proxy in front will typically answer 502). Apache respawns the child; the next request works.
- `session.upload_progress` never records progress, whatever `php.ini` / `.htaccess` says.
- New INI `max_multipart_body_parts` (default `-1` = `max_input_vars + max_file_uploads`).
- Default config `/usr/local/etc/php/conf.d/zz-php2shell-mitigations.ini` (the officially
  recommended php2shell config mitigations, not present in the official image):
  - `session.upload_progress.enabled = 0` — belt and braces; the patch already suppresses
    upload progress regardless of this setting.
  - `memory_limit = -1` — keeps scripts away from the `memory_limit` fatal path. **This means
    no PHP memory cap by default** (the official image, which ships no `php.ini`, defaulted to
    `128M`); bound memory with container limits. If an allocation still fails, the patched OOM
    path `_exit(1)`s the child as described above.

  Downstream images can override these with a later-sorting `conf.d` file, `php_value` in the
  Apache config / `.htaccess`, or `ini_set()` (for `memory_limit`).

Other fatal errors still unwind with `longjmp()`; this is a mitigation, not a complete fix.

## Tests

```bash
sh test/run.sh php:5.4.45-apache-cve
```

Starts the image on a private docker network (`apachetest54`, container `ap54`, no published
ports), mounts `test/www` as `/var/www/html` and drives it over HTTP from a
`curlimages/curl` container (`test/tests.sh`). Per-scenario INI overrides come from
`.htaccess` files (`AllowOverride All` is set on `/var/www/` by the official `apache2.conf`).
Observed results:

| Test | Unpatched 5.4.45 | Patched |
|---|---|---|
| Response headers | `X-Powered-By: PHP/5.4.45`, `Server: Apache/2.4.10 (Debian) PHP/5.4.45` | `X-Powered-By: php-a-mnx`, `Server: Apache/2.4.10 (Debian) php-a-mnx` |
| Defaults | `memory_limit=128M`, upload progress on | `memory_limit=-1`, upload progress off |
| Upload progress re-enabled in `.htaccess`, session cookie | writes `upload_progress_*` to session | nothing written |
| `max_multipart_body_parts=3` | unknown INI, all parts parsed | warning, stops after 3 parts |
| OOM (`ini_set('memory_limit','16M')`) | fatal in the response, shutdown function runs, child keeps serving | empty reply, child exits(1), next request OK |
| `max_execution_time` (`set_time_limit(1)`) | fatal in the response, shutdown function runs | empty reply, child exits(1), next request OK |

The PHP 5.4 `make test` suite has **not** been run.

## License

The patches modify PHP source code and is distributed under the
[PHP License 3.01](https://www.php.net/license/3_01.txt). The Dockerfile, `apache2.conf`,
`apache2-foreground` and helper scripts are derived from
[docker-library/php](https://github.com/docker-library/php) (MIT).
