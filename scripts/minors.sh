#!/usr/bin/env bash
# Lists the PHP versions this repository builds, one per line, oldest first: every top-level
# directory named <major>.<minor> with a Dockerfile in it. Adding a directory adds an image;
# the build matrix and the daily check both read this list.
set -euo pipefail

cd "$(dirname "$0")/.."

for dir in [0-9]*.[0-9]*
do
    if [ -f "$dir/Dockerfile" ]
    then
        echo "$dir"
    fi
done | sort -V
