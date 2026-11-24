# PHP 8.6 FPM with the extensions the sites on the server need.
#
# The image is the same for every site: the FPM pools (www.conf) and the php.ini settings are
# not part of it. The server mounts them (see README), so a pool change needs no new image.
#
# BASE is set by the build workflow to php:8.6-fpm@sha256:<digest>, so every image records
# the exact base it was built from (label org.opencontainers.image.base.digest). The default
# is only for a build by hand.
ARG BASE=php:8.6-fpm
FROM ${BASE}

# Two differences of the official 8.6 images from 8.5 (docker-library/php):
# - mbstring is no longer compiled into the base image. --enable-mbstring was only there for
#   pecl, and pecl/PEAR was dropped for 8.6 (PR #1654; Dockerfile-linux.template, condition
#   install_pear_pecl = 8.2 to 8.5). So it is built here, with Oniguruma (libonig-dev) for
#   mb_ereg*, as 8.4 and 8.5 have it. mbregex is deprecated in 8.6 (RFC eol-oniguruma) but
#   still works.
# - Every 8.6+ image is a thread-safe (ZTS) build (PR #1686), because PHP plans to drop the
#   non-thread-safe build with 9.0. All extensions below are part of php-src and build for ZTS.
# exif: on the WordPress hosting handbook's "highly recommended" list (image metadata).
# igbinary and imagick from the same list are left out on purpose: igbinary only pays off
# with an object cache, and GD already covers image handling without ImageMagick.
# opcache is built into the core since PHP 8.5 and must be neither installed nor enabled.
RUN apt-get update && apt-get install -y \
    libicu-dev libzip-dev libpng-dev libjpeg62-turbo-dev libwebp-dev libpq-dev libonig-dev \
    && docker-php-ext-configure gd --with-jpeg --with-webp \
    && docker-php-ext-install -j "$(nproc)" \
    mysqli pdo_mysql pdo_pgsql pgsql intl zip gd exif mbstring \
    && rm -rf /var/lib/apt/lists/*

# No CMD of our own: the base image's "php-fpm" runs in the foreground (daemonize = no in
# zz-docker.conf), and FPM removes a stale Unix socket itself before it binds - it connects
# first, and if nobody listens it unlinks the file (php-src sapi/fpm/fpm/fpm_sockets.c,
# "Another FPM instance seems to already listen"). tests/test-image.sh checks that.
