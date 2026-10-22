# untested-php2shell-fixed-php-fpm-mod_php

> **UNTESTED, UNOFFICIAL, NO WARRANTY.** Best-effort builds of end-of-life PHP versions with
> a mitigation for **php2shell** — [CVE-2026-109618](https://github.com/php/php-src/security/advisories/GHSA-w8hw-w9fx-j79w)
> and [CVE-2026-109619](https://github.com/php/php-src/security/advisories/GHSA-6wmf-4rv5-p3rp).
> None of this has been reviewed by the PHP project. EOL PHP versions have many other known,
> unfixed vulnerabilities: migrate off them.

This repository exists because a vulnerability of this magnitude also needed mitigating
on PHP versions that, while long past end of life, are well known to still be widely
deployed on the Internet and received no official fix.

Drop-in replacements for the official [docker-library/php](https://github.com/docker-library/php)
images, rebuilt from the same recipes with security patches applied. One image tag per
version/SAPI combination, docker-library style:

```bash
docker pull ghcr.io/manuxio/untested-php2shell-fixed-php-fpm-mod_php:<version>-<sapi>
```

| Tag | Base recipe | Patch source | Directory |
|---|---|---|---|
| `5.4.45-fpm` | php:5.4-fpm (jessie) | hand backport of the upstream 7.4 minimal mitigation | [5.4.45-fpm](5.4.45-fpm/) |
| `5.4.45-apache` | php:5.4-apache (jessie) | same patch | [5.4.45-apache](5.4.45-apache/) |
| `7.2.34-fpm` | php:7.2-fpm (buster) | hand port of the upstream 7.4 minimal mitigation | [7.2.34-fpm](7.2.34-fpm/) |
| `7.2.34-apache` | php:7.2-apache (buster) | same patch | [7.2.34-apache](7.2.34-apache/) |
| `7.4.32-apache` | php:7.4-apache (bullseye) | upstream 7.4 minimal mitigation, unmodified | [7.4-apache](7.4-apache/) |
| `7.4.33-apache` | php:7.4-apache (bullseye) | upstream 7.4 minimal mitigation, unmodified | [7.4-apache](7.4-apache/) |
| `8.0.24-apache` | php:8.0-apache (bullseye) | Remi's php80 backport (+ official CVE-2023-0662 prerequisite) | [8.0-apache](8.0-apache/) |
| `8.0.26-apache` | php:8.0-apache (bullseye) | Remi's php80 backport (+ official CVE-2023-0662 prerequisite) | [8.0-apache](8.0-apache/) |
| `8.0.28-apache` | php:8.0-apache (bullseye) | Remi's php80 backport | [8.0-apache](8.0-apache/) |

Minor-version alias tags (`5.4-fpm`, `7.2-apache`, `7.4-apache`, ...) point to the latest
patched release of that family. 5.4.45, 7.2.34 and 7.4.33 are the final releases of their
families. The 8.0 and 8.1 families are being added with the best available patch source
(Remi's backports).

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

## Credits

- **Remi Collet** and his PHP repository — [remirepo](https://rpms.remirepo.net/)
  ([git.remirepo.net](https://git.remirepo.net/cgit/rpms/php/), [github.com/remicollet](https://github.com/remicollet)) —
  for maintaining the official-quality security backports of the php2shell fix for
  EOL PHP branches (7.4, 8.0, 8.1), which this repo uses or cross-checks its patches against.
- **docker-library/php** maintainers for the original image recipes.

## License

The patches modify PHP source code and are distributed under the
[PHP License 3.01](https://www.php.net/license/3_01.txt). Dockerfiles and helper
scripts are derived from [docker-library/php](https://github.com/docker-library/php) (MIT).
