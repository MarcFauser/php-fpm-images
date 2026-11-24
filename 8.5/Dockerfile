# PHP 8.5 FPM with the extensions the sites on the server need.
#
# The image is the same for every site: the FPM pools (www.conf) and the php.ini settings are
# not part of it. The server mounts them (see README), so a pool change needs no new image.
#
# BASE is set by the build workflow to php:8.5-fpm@sha256:<digest>, so every image records
# the exact base it was built from (label org.opencontainers.image.base.digest). The default
# is only for a build by hand.
ARG BASE=php:8.5-fpm
FROM ${BASE}

# exif: on the WordPress hosting handbook's "highly recommended" list (image metadata).
# igbinary and imagick from the same list are left out on purpose: igbinary only pays off
# with an object cache, and GD already covers image handling without ImageMagick.
# opcache is built into the core since PHP 8.5 and must be neither installed nor enabled.
RUN apt-get update && apt-get install -y \
    libicu-dev libzip-dev libpng-dev libjpeg62-turbo-dev libwebp-dev libpq-dev \
    && docker-php-ext-configure gd --with-jpeg --with-webp \
    && docker-php-ext-install -j "$(nproc)" \
    mysqli pdo_mysql pdo_pgsql pgsql intl zip gd exif \
    && rm -rf /var/lib/apt/lists/*

# No CMD of our own: the base image's "php-fpm" runs in the foreground (daemonize = no in
# zz-docker.conf), and FPM removes a stale Unix socket itself before it binds - it connects
# first, and if nobody listens it unlinks the file (php-src sapi/fpm/fpm/fpm_sockets.c,
# "Another FPM instance seems to already listen"). tests/test-image.sh checks that.
