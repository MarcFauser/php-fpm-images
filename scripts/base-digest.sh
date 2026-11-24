#!/usr/bin/env bash
# Prints the digest (sha256:...) an official Docker Hub tag points to right now, for example
#   scripts/base-digest.sh php:8.6-fpm
# It is the digest of the multi-architecture index, the same value "docker pull" records as
# RepoDigest and Docker Hub shows for the tag. Exits non-zero if the tag does not exist (or
# the registry cannot be reached), so "is there a php:8.7-fpm yet?" is the exit status.
#
# Only a HEAD request on the manifest: Docker Hub does not count HEAD requests against the
# pull rate limit.
set -euo pipefail

ref="${1:?usage: base-digest.sh <image>:<tag>}"
repo="${ref%%:*}"
tag="${ref#*:}"

token="$(curl -fsS "https://auth.docker.io/token?service=registry.docker.io&scope=repository:library/${repo}:pull" | jq -r .token)"

# The headers are captured first and searched afterwards, and awk reads to the end: under
# pipefail, a reader that stops early (grep -q, head) can make curl die of SIGPIPE and turn
# a found digest into a failure.
headers="$(curl -fsSI \
    -H "Authorization: Bearer ${token}" \
    -H 'Accept: application/vnd.oci.image.index.v1+json, application/vnd.docker.distribution.manifest.list.v2+json, application/vnd.oci.image.manifest.v1+json, application/vnd.docker.distribution.manifest.v2+json' \
    "https://registry-1.docker.io/v2/library/${repo}/manifests/${tag}")"

digest="$(printf '%s\n' "$headers" | tr -d '\r' | awk -F': ' 'tolower($1) == "docker-content-digest" { d = $2 } END { print d }')"

case "$digest" in
    sha256:*) echo "$digest" ;;
    *) echo "no digest for ${ref}" >&2; exit 1 ;;
esac
