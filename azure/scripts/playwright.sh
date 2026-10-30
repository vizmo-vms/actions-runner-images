#!/usr/bin/env bash
# Chromium for each pinned Playwright version, in the runner's default browser cache (~/.cache/ms-playwright), plus
# the system libraries `playwright install --with-deps` would apt-get install.
#
# Usage: playwright.sh base|large   large installs PLAYWRIGHT_VERSIONS_LARGE on top of runner-base
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
. "$here/versions.env"

versions=${PLAYWRIGHT_VERSIONS}
[ "$1" = large ] && versions=${PLAYWRIGHT_VERSIONS_LARGE}
node_bin="/usr/local/nvm/versions/node/v${NODE_VERSION}/bin"
for version in ${versions}; do
  PATH="$node_bin:$PATH" npx --yes "playwright@${version}" install-deps chromium
  runuser -l runner -s /bin/bash -c "npx --yes 'playwright@${version}' install chromium"
done
runuser -l runner -s /bin/bash -c "npm cache clean --force"
rm -rf /root/.npm
