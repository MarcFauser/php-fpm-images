# History

A narrative log of how this project came to be. The structured, versioned list of changes
lives in CHANGELOG.md; this file records the reasoning.

## 2026-11-25: from building on the server to building on GitHub

The web server ran PHP 8.4 and 8.5 as FPM containers, each built on the server from a
Dockerfile that a setup script wrote, with a pool configuration copied into the image. A
PHP 8.6 container was to be added (PHP 8.6.0 was released on 2026-11-19, the official
`php:8.6-fpm` image appeared on 2026-11-24). Two things came up while preparing it:

- **The 8.6 base image is built differently.** docker-library/php dropped pecl/PEAR for 8.6
  (PR #1654), and `--enable-mbstring` was compiled in only for pecl (template condition
  `install_pear_pecl`, 8.2 to 8.5), so mbstring is gone from the base image; and every image
  from 8.6 on is a ZTS build (PR #1686). PHP's 8.6 UPGRADING lists no removed extension and
  only small API changes for the ones used here; mbregex is deprecated (RFC eol-oniguruma).
  So the 8.6 Dockerfile builds mbstring with Oniguruma, to match what 8.4 and 8.5 have.
- **The server's base images were already out of date**: Docker Hub's digests for
  `php:8.4-fpm` and `php:8.5-fpm` differed from the ones on the server, and nothing would
  have said so until the next manual run of the setup script.

Hence the question: build on GitHub, so the server builds nothing and a new base image is
noticed by itself. Decisions:

- **Own images, not ready-made ones.** The official `wordpress:fpm` image contains WordPress
  itself and imagick, but no pgsql or pdo_pgsql. serversideup/php (GPL-3.0) ships mbstring,
  opcache, pcntl, pdo_mysql, pdo_pgsql, redis and zip by default, but not mysqli, gd, intl,
  exif or pgsql, so it would need a build as well, and it is a third party with root in the
  container.
- **One image for every site; pools and php.ini stay on the server and are mounted.** The
  old images had the pool copied in, which tied an image to the server's sites and made
  every pool change a rebuild. Without it the image contains nothing about the sites, can be
  public, and the server pulls without credentials. The per-version `CMD` that removed a
  stale socket is gone: FPM connects to an existing socket file first and unlinks it if
  nobody listens (php-src PHP-8.5 `sapi/fpm/fpm/fpm_sockets.c`, lines 223-228); the tests
  leave such a socket behind on purpose.
- **A fingerprint decides whether to publish**, not the run: sha256 over the base digest and
  the Dockerfile, compared with `published.txt`. Otherwise every run would push a new image
  with the same content, and the server would restart its PHP containers for nothing.
- **A daily check of our own instead of Dependabot.** Read in dependabot-core
  (`docker/update_checker.rb`): for a tag like `8.5-fpm` it proposes the next tag of the same
  precision (`8.6-fpm`), and its digest-only updates of versioned tags are subject to the
  experiment `docker_digest_only_update_suppression`, whose state on github.com is not
  visible. The check asks Docker Hub directly (HEAD requests on the manifest, which do not
  count against the pull rate limit).
- **A new PHP minor opens an issue, it is not built automatically**: a new minor needs a new
  container and its configuration on the server, which is a decision.
- **Like caddy-deb**, the daily trigger is a workflow of its own (check.yml), because GitHub
  disables a scheduled workflow after 60 days without repository activity, with all its
  triggers; build.yml keeps working on pushes.
- The test module lists for 8.4 and 8.5 were taken from the running containers on the
  server (`php -m`, 2026-11-25); the 8.6 list starts as a copy of 8.5's, and the first build
  shows whether 8.6 brings or drops a module.
