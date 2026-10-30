#!/usr/bin/env bash
# Node through nvm at NVM_DIR, as the ARC image provides it (platform's runner-node action selects it from there),
# plus Node builds in the tool cache for actions/setup-node.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
. "$here/versions.env"

export NVM_DIR=/usr/local/nvm
mkdir -p "$NVM_DIR"
curl -fsSL "https://raw.githubusercontent.com/nvm-sh/nvm/${NVM_VERSION}/install.sh" | PROFILE=/dev/null bash
# nvm.sh reads unset variables, so it runs without -u.
set +u
. "$NVM_DIR/nvm.sh"
nvm install "${NODE_VERSION}"
nvm alias default "${NODE_VERSION}"
npm install --global "pnpm@${PNPM_VERSION}"
nvm cache clear
set -u
# Jobs may nvm install other versions or npm install -g into this prefix.
chown -R runner:runner "$NVM_DIR"

for version in ${TOOLCACHE_NODE_VERSIONS}; do
  dir="/opt/hostedtoolcache/node/${version}/x64"
  mkdir -p "$dir"
  curl -fsSL "https://nodejs.org/dist/v${version}/node-v${version}-linux-x64.tar.xz" | tar -xJ --strip-components=1 -C "$dir"
  touch "${dir}.complete"
done
