# untested-php2shell-fixed-php

> **UNTESTED, UNOFFICIAL, NO WARRANTY.** Best-effort builds of end-of-life PHP versions with
> a mitigation for **php2shell** — [CVE-2026-109618](https://github.com/php/php-src/security/advisories/GHSA-w8hw-w9fx-j79w)
> and [CVE-2026-109619](https://github.com/php/php-src/security/advisories/GHSA-6wmf-4rv5-p3rp).
> None of this has been reviewed by the PHP project. EOL PHP versions have many other known,
> unfixed vulnerabilities: migrate off them.

Drop-in replacements for the official [docker-library/php](https://github.com/docker-library/php)
images, rebuilt from the same recipes with security patches applied. One image tag per
version/SAPI combination, docker-library style:

```bash
docker pull ghcr.io/manuxio/untested-php2shell-fixed-php:<version>-<sapi>
```

| Tag | Base recipe | Patch source | Directory |
|---|---|---|---|
| `5.4.45-fpm` | php:5.4-fpm (jessie) | hand backport of the upstream 7.4 minimal mitigation | [5.4.45-fpm](5.4.45-fpm/) |
| `5.4.45-apache` | php:5.4-apache (jessie) | same patch | [5.4.45-apache](5.4.45-apache/) |
| `7.2.34-fpm` | php:7.2-fpm (buster) | hand port of the upstream 7.4 minimal mitigation | [7.2.34-fpm](7.2.34-fpm/) |
| `7.2.34-apache` | php:7.2-apache (buster) | same patch | [7.2.34-apache](7.2.34-apache/) |

7.2.34 is the final PHP 7.2 release; 5.4.45 the final 5.4. Further version families
(7.4, 8.0, 8.1) are being added with the best available patch source for each
(upstream 7.4 patch; Remi's backports for 8.0/8.1).

## Common changes vs the official images

Every image in this repo:

- applies the php2shell mitigation patch (`php-<branch>-CVE-2026-109618-109619.patch`
  in each directory, applied with `patch -p1 --fuzz=0`; per-directory READMEs document
  the exact port)
- masks the PHP version in server signatures (`php-<branch>-mask-server-signature.patch`):
  `X-Powered-By` and the Apache `Server` token report `php-a-mnx` (PHP 5), `php-b-mnx`
  (PHP 7) or `php-c-mnx` (PHP 8) instead of the real version; `phpversion()` /
  `PHP_VERSION` are untouched
- bakes in the recommended mitigations as defaults (`conf.d/zz-php2shell-mitigations.ini`,
  overridable downstream): `session.upload_progress.enabled=0`, `memory_limit=-1`;
  FPM images additionally set `pm.max_requests=1`
- keeps everything else identical to the official recipe (packages, configure flags,
  entrypoints, EXPOSE/CMD), so downstream Dockerfiles only change their `FROM`

Behaviour changes caused by the patch (worker terminates on OOM/timeout instead of
unwinding, upload progress never recorded, new `max_multipart_body_parts` INI) are
documented per directory.

## Tests

Each directory ships a functional `test/` harness:

```bash
sh <dir>/test/run.sh <image>
```

## License

The patches modify PHP source code and are distributed under the
[PHP License 3.01](https://www.php.net/license/3_01.txt). Dockerfiles and helper
scripts are derived from [docker-library/php](https://github.com/docker-library/php) (MIT).
