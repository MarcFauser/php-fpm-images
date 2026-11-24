# php-fpm-images

PHP-FPM images for a web server that runs PHP in containers behind Caddy, one container per
PHP version, connected over Unix sockets. GitHub Actions builds, tests and publishes them,
so the server only pulls them.

```
ghcr.io/marcfauser/php-fpm-images:8.4
ghcr.io/marcfauser/php-fpm-images:8.5
ghcr.io/marcfauser/php-fpm-images:8.6
```

## What is in an image

The official `php:<minor>-fpm` image (Debian trixie) plus the extensions the sites need:
mysqli, pdo_mysql, pdo_pgsql, pgsql, intl, zip, gd (JPEG, PNG, WebP) and exif. The exact
module list of each image is in `<minor>/modules.txt`, and the build fails if the image
differs from it.

| | 8.4 | 8.5 | 8.6 |
|---|---|---|---|
| opcache | extension, installed here | built into PHP | built into PHP |
| mbstring | from the base image | from the base image | **built here**: the 8.6 base image no longer has it |
| thread safety | NTS | NTS | **ZTS**: every official image from 8.6 on |

Both 8.6 differences come from docker-library/php: PR #1654 dropped pecl/PEAR for 8.6, and
`--enable-mbstring` was only compiled in for pecl; PR #1686 builds every 8.6+ image as ZTS,
because PHP plans to drop the non-thread-safe build with 9.0.

**Not in the image: the FPM pools and php.ini.** The server mounts its own `www.conf` as
`/usr/local/etc/php-fpm.d/zz-custom.conf` and its ini as
`/usr/local/etc/php/conf.d/custom.ini`, so one image serves every site, a pool change needs
no new image, and the image contains nothing about the sites. The image keeps the base's
`CMD ["php-fpm"]`; FPM removes a stale Unix socket itself before it binds (php-src
`sapi/fpm/fpm/fpm_sockets.c`), and the tests check that.

## Tags

| tag | moves when | for |
|---|---|---|
| `8.6` | every publish of 8.6 | the server |
| `8.6.0` | every publish with PHP 8.6.0 | pinning a PHP version |
| `8.6.0-20261125.041200` | never | going back to exactly this image |

Every image carries OCI labels: `org.opencontainers.image.base.digest` (the exact
`php:<minor>-fpm` it was built from), `org.opencontainers.image.revision` (the commit),
`org.opencontainers.image.version` (PHP), `io.github.marcfauser.php-fpm-images.version`
(this repository, from `CHANGELOG.md`) and `…fingerprint` (see below).

```
docker image inspect -f '{{json .Config.Labels}}' ghcr.io/marcfauser/php-fpm-images:8.6
```

## How it is built

- **`.github/workflows/build.yml`**: one job per `<major>.<minor>` directory
  (`scripts/minors.sh`). It resolves the digest `php:<minor>-fpm` points to
  (`scripts/base-digest.sh`), builds `FROM php:<minor>-fpm@sha256:…`, runs
  `tests/test-image.sh`, and publishes only if the **fingerprint** (sha256 over the base
  digest and the Dockerfile) differs from the one in `published.txt`, or if started with
  `force`. An unchanged image is never pushed again, so the server has nothing to pull. The
  record job then commits the new lines of `published.txt`. Pull requests build and test
  only.
- **`.github/workflows/check.yml`**, daily at 04:23 UTC: starts `build.yml` when Docker Hub's
  digest of a `php:<minor>-fpm` differs from `published.txt` (Debian updates, PHP patch
  releases), and opens an issue when a `php:<next minor>-fpm` exists. GitHub mails new
  issues and failed scheduled runs to the repository's owner.
- **`tests/test-image.sh`**: the module list (`php -m` and `php-fpm -m`), `php-fpm -t` with a
  pool like the server's (`tests/pool.conf`), and a real FastCGI request through a Unix socket
  that a dead FPM left behind, to `tests/probe.php`, which checks every extension and the
  pool's restrictions (open_basedir, disable_functions) from inside FPM.

Why not Dependabot for the base images: for a tag like `8.5-fpm` it proposes the next tag of
the same precision (`8.6-fpm`), while each minor here has to stay on its own; and its
digest-only updates for versioned tags can be switched off by an experiment
(`docker_digest_only_update_suppression`, dependabot-core `docker/update_checker.rb`).

GitHub disables a scheduled workflow after 60 days without repository activity. The record
job's commits count as activity whenever a base image changes; if the check was disabled
anyway: `gh workflow enable check.yml --repo MarcFauser/php-fpm-images`.

## A new PHP minor

1. Copy the highest `<minor>/` directory to the new one and adjust the `Dockerfile` (read the
   PHP `UPGRADING` notes and the docker-library/php changes for that version first).
2. Push. The build fails on the module list if the new version brings or drops a module:
   look at the diff in the log, decide, and update `<minor>/modules.txt`.
3. On the server: a compose service, `www.conf` and ini for it (the setup script there).

## On the server

A compose service, with the host folder that holds the sockets, pools and logs mounted as
`/run/php` (paths here are examples):

```yaml
  php86:
    image: ghcr.io/marcfauser/php-fpm-images:8.6
    volumes:
      - /srv/php:/run/php
      - /srv/php/php86/www.conf:/usr/local/etc/php-fpm.d/zz-custom.conf:ro
      - /srv/php/php86.ini:/usr/local/etc/php/conf.d/custom.ini:ro
      - /run/mysqld:/run/mysqld:ro            # database sockets, if the sites use them
      - /run/postgresql:/run/postgresql:ro
    restart: unless-stopped
```

Update: `docker compose pull && docker compose up -d`. Back to an earlier image: put its
dated tag into `image:` and run the same.

## Working on this repository

After cloning, install the git hooks once: `./install-git-hooks.ps1` (or
`install-git-hooks.cmd`). The pre-commit hook requires a new version section in
`CHANGELOG.md` with every commit.

## License

MIT, see `LICENSE`. That covers this repository; the images contain PHP, Debian and the
other software of the official `php` image under their own licenses.
