#!/usr/bin/env bash
# Pulls container images jobs start, so docker compose and docker build find them locally. Every image is public, so
# the build pulls them anonymously.
#
# Usage: images.sh <list>   one image reference per line; # starts a comment
set -euo pipefail

list=$1
mapfile -t refs < <(sed -e 's/#.*//' -e 's/[[:space:]]*$//' "$list" | grep -v '^$')

printf '%s\n' "${refs[@]}" | xargs -P 4 -n 1 docker pull --quiet

# runner-image-check confirms these are still present on every boot test.
mkdir -p /etc/runner-image
printf '%s\n' "${refs[@]}" >>/etc/runner-image/images.txt
