# Changelog

All notable changes to this project are documented in this file.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project
uses [Semantic Versioning](https://semver.org/spec/v2.0.0.html). This is the version of the
repository (Dockerfiles, tests, workflows); every image carries it in the label
`io.github.marcfauser.php-fpm-images.version`. The image tags follow PHP.

## [1.0.1] - 2026-11-25

### Fixed

- The stale-socket test told the stale socket and FPM's new one apart by the inode number,
  and failed for all three images in the first run although FPM had replaced the socket:
  ext4 gave the new socket the inode it had just freed. It now compares the owner (the
  runner's user before, www-data afterwards).

### Changed

- The Dockerfiles use `apt` instead of `apt-get`, and `tests/probe.php` puts every opening
  brace on its own line, as the conventions of the server project ask.

## [1.0.0] - 2026-11-25

### Added

- PHP-FPM images for PHP 8.4, 8.5 and 8.6 on the official `php:<minor>-fpm` (Debian trixie),
  with mysqli, pdo_mysql, pdo_pgsql, pgsql, intl, zip, gd (JPEG, PNG, WebP) and exif; 8.4
  also with the opcache extension, 8.6 with mbstring built in, which its base image no longer
  contains. Pools and php.ini are not part of the images: the server mounts them.
- Tests before every publish: the module list against `<minor>/modules.txt`, `php-fpm -t`
  with a pool like the server's, and a FastCGI request through a Unix socket that a dead FPM
  left behind, to a probe that checks every extension and the pool's restrictions
  (open_basedir, disable_functions) from inside FPM.
- Publishing to `ghcr.io/marcfauser/php-fpm-images` with the tags `<minor>`, `<php version>`
  and `<php version>-<date>.<time>`, only when the base image or the Dockerfile changed;
  `published.txt` records what was published.
- A daily check against Docker Hub that starts a build when a base image changed and opens
  an issue when a newer PHP minor exists.
