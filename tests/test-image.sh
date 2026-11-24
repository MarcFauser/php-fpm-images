#!/usr/bin/env bash
# Tests one built image before it is published:
#   tests/test-image.sh <image> <minor>        e.g. tests/test-image.sh local/php-fpm:8.6 8.6
#
# 1. "php -m" and "php-fpm -m" list exactly the modules in <minor>/modules.txt - a module
#    that goes missing (as mbstring did with the 8.6 base image) or appears fails the build.
# 2. "php-fpm -t" accepts a pool built like the server's (tests/pool.conf).
# 3. A stale Unix socket is left where the pool listens, FPM is started, and a real FastCGI
#    request goes through the socket to tests/probe.php, which checks every extension and
#    the pool's restrictions from inside FPM. This also proves that FPM removes a stale
#    socket by itself, which is why the image needs no CMD of its own.
#
# Needs docker, python3 and cgi-fcgi (Debian/Ubuntu package libfcgi-bin).
set -euo pipefail

image="${1:?usage: test-image.sh <image> <minor>}"
minor="${2:?usage: test-image.sh <image> <minor>}"

here="$(cd "$(dirname "$0")" && pwd)"
root="$(dirname "$here")"
expected="$root/$minor/modules.txt"
[ -f "$expected" ] || { echo "FAIL: $expected not found" >&2; exit 1; }

work="$(mktemp -d)"
name="php-fpm-test-${minor}-$$"

cleanup()
{
    docker rm -f "$name" > /dev/null 2>&1 || true
    # The container wrote into $work as root and as www-data; on a CI runner the VM is thrown
    # away afterwards anyway.
    rm -rf "$work" 2> /dev/null || true
}
trap cleanup EXIT

fail()
{
    echo "FAIL: $*" >&2
    if docker container inspect "$name" > /dev/null 2>&1
    then
        echo "--- container log" >&2
        docker logs "$name" >&2 2>&1 || true
    fi
    for log in "$work/run/error.log" "$work/run/access.log"
    do
        if [ -s "$log" ]
        then
            echo "--- $(basename "$log")" >&2
            cat "$log" >&2 || true
        fi
    done
    exit 1
}

# --- 1. module lists ---

echo "== modules"
docker run --rm "$image" php -m | sed '/^$/d' > "$work/cli.txt"
diff -u "$expected" "$work/cli.txt" || fail "php -m differs from $minor/modules.txt (- expected, + image)"

# php-fpm also lists its own SAPI module cgi-fcgi; apart from that the lists must match.
docker run --rm "$image" php-fpm -m | sed '/^$/d' | sed '/^cgi-fcgi$/d' > "$work/fpm.txt"
diff -u "$expected" "$work/fpm.txt" || fail "php-fpm -m differs from $minor/modules.txt (- expected, + image)"
echo "ok: $(grep -c . "$expected") lines as in $minor/modules.txt"

# --- 2. configuration test ---

mkdir -p "$work/run/tmp"
# The pool's workers run as www-data and write the error log and temp files here.
chmod -R 0777 "$work/run"

mounts=(
    -v "$here/pool.conf:/usr/local/etc/php-fpm.d/zz-custom.conf:ro"
    -v "$here/php.ini:/usr/local/etc/php/conf.d/custom.ini:ro"
    -v "$here/probe.php:/srv/site/probe.php:ro"
    -v "$work/run:/run/php"
)

echo "== php-fpm -t"
docker run --rm "${mounts[@]}" "$image" php-fpm -t || fail "php-fpm -t rejected the test pool"

# --- 3. FastCGI request through a socket that a dead FPM left behind ---

python3 -c 'import socket, sys; s = socket.socket(socket.AF_UNIX); s.bind(sys.argv[1]); s.close()' "$work/run/test.sock"
[ -S "$work/run/test.sock" ] || fail "could not create the stale socket for the test"
stale_inode="$(stat -c %i "$work/run/test.sock")"

echo "== start FPM"
docker run -d --name "$name" "${mounts[@]}" "$image" > /dev/null

# The log is captured first and searched afterwards: "docker logs | grep -q" under pipefail
# can fail on a match, because grep -q stops reading and docker logs dies of SIGPIPE.
ready=0
for _ in $(seq 1 60)
do
    logs="$(docker logs "$name" 2>&1)"
    if grep -q 'ready to handle connections' <<< "$logs"
    then
        ready=1
        break
    fi
    if [ "$(docker inspect -f '{{.State.Running}}' "$name")" != true ]
    then
        fail "FPM stopped during startup"
    fi
    sleep 0.5
done
[ "$ready" -eq 1 ] || fail "FPM did not become ready within 30 s"
[ -S "$work/run/test.sock" ] || fail "FPM did not create its socket"
[ "$(stat -c %i "$work/run/test.sock")" != "$stale_inode" ] || fail "the socket is still the stale one"
echo "ok: FPM replaced the stale socket and is ready"

echo "== FastCGI request"
# env -i: cgi-fcgi passes its whole environment as FastCGI parameters, so only the request's
# own parameters are given, nothing from the runner.
fcgi="$(command -v cgi-fcgi)" || fail "cgi-fcgi not found (package libfcgi-bin)"
env -i \
    SCRIPT_FILENAME=/srv/site/probe.php \
    SCRIPT_NAME=/probe.php \
    REQUEST_URI="/probe.php?minor=${minor}" \
    QUERY_STRING="minor=${minor}" \
    REQUEST_METHOD=GET \
    SERVER_NAME=probe.test \
    SERVER_PROTOCOL=HTTP/1.1 \
    "$fcgi" -bind -connect "$work/run/test.sock" > "$work/response.txt" \
    || fail "the FastCGI request failed"

tr -d '\r' < "$work/response.txt" > "$work/response.lf"
cat "$work/response.lf"

if grep -qi '^X-Powered-By:' "$work/response.lf"
then
    fail "X-Powered-By header present (expose_php is not off)"
fi
if grep -q '^FAIL ' "$work/response.lf"
then
    fail "probe.php reported failures"
fi
grep -q '^done [0-9][0-9]*$' "$work/response.lf" || fail "probe.php did not finish"

# The probe triggers no error on purpose; anything in the error log is unexpected.
if [ -s "$work/run/error.log" ]
then
    fail "the pool's error log is not empty"
fi
logs="$(docker logs "$name" 2>&1)"
unexpected="$(grep -E '(ERROR|WARNING|NOTICE): ' <<< "$logs" | grep -vE 'NOTICE: (fpm is running|ready to handle connections)' || true)"
if [ -n "$unexpected" ]
then
    echo "$unexpected" >&2
    fail "FPM logged warnings or errors"
fi

echo "== all tests passed for $image (PHP $minor)"
