#!/usr/bin/env bash
# Pulls container images jobs start, so docker compose and docker build find them locally.
#
# Usage: images.sh <list>   one image reference per line; # starts a comment
# GHCR_TOKEN reads the private ghcr.io/vizmo-vms images. Without it they fail the build, unless
# ALLOW_MISSING_PRIVATE_IMAGES=true (local test builds), which skips them.
set -euo pipefail

list=$1
mapfile -t refs < <(sed -e 's/#.*//' -e 's/[[:space:]]*$//' "$list" | grep -v '^$')

if [ -n "${GHCR_TOKEN:-}" ]; then
  echo "$GHCR_TOKEN" | docker login ghcr.io --username token --password-stdin
fi

pull=()
for ref in "${refs[@]}"; do
  if [[ "$ref" == ghcr.io/vizmo-vms/* && -z "${GHCR_TOKEN:-}" ]]; then
    if [ "${ALLOW_MISSING_PRIVATE_IMAGES:-false}" = true ]; then
      echo "::warning::skipping private image without GHCR_TOKEN: $ref"
      continue
    fi
    echo "GHCR_TOKEN is needed to pull $ref" >&2
    exit 1
  fi
  pull+=("$ref")
done

status=0
printf '%s\n' "${pull[@]}" | xargs -P 4 -n 1 docker pull --quiet || status=$?
docker logout ghcr.io >/dev/null 2>&1 || true
rm -f /root/.docker/config.json
[ "$status" -eq 0 ] || exit "$status"

# runner-image-check confirms these are still present on every boot test.
mkdir -p /etc/runner-image
printf '%s\n' "${pull[@]}" >>/etc/runner-image/images.txt
