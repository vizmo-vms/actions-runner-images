#!/usr/bin/env bash
# Chromium for each Playwright version platform and argus pin, in the runner's default browser cache
# (~/.cache/ms-playwright), plus the system libraries `playwright install --with-deps` would apt-get install.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
. "$here/versions.env"

node_bin="/usr/local/nvm/versions/node/v${NODE_VERSION}/bin"
for version in ${PLAYWRIGHT_VERSIONS}; do
  PATH="$node_bin:$PATH" npx --yes "playwright@${version}" install-deps chromium
  runuser -l runner -s /bin/bash -c "npx --yes 'playwright@${version}' install chromium"
done
runuser -l runner -s /bin/bash -c "npm cache clean --force"
rm -rf /root/.npm
