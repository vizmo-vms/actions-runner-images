#!/usr/bin/env bash
# The runner user GARM's cloud-init expects, with the GitHub runner already unpacked in its home. GARM's install
# script skips the download and dependency install when /home/runner/actions-runner exists, so boot only registers.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
. "$here/versions.env"

id runner >/dev/null 2>&1 || useradd --create-home --shell /bin/bash runner
# The groups GARM gives its default user, plus the journal for debugging.
for group in sudo adm cdrom dialout dip video plugdev netdev docker lxd systemd-journal; do
  getent group "$group" >/dev/null && usermod -aG "$group" runner
done
echo 'runner ALL=(ALL) NOPASSWD:ALL' >/etc/sudoers.d/90-runner
chmod 0440 /etc/sudoers.d/90-runner

# Login shells (GARM starts the install script with `su -l`) pick these up; the runner's env.sh then copies PATH
# into .path, which becomes every job's PATH.
cat >/etc/profile.d/runner-image.sh <<EOF
export NVM_DIR=/usr/local/nvm
export RUNNER_TOOL_CACHE=/opt/hostedtoolcache
export AGENT_TOOLSDIRECTORY=/opt/hostedtoolcache
export ANDROID_HOME=/opt/android-sdk
export ANDROID_SDK_ROOT=/opt/android-sdk
export JAVA_HOME=/opt/java-17
export PATH="/home/runner/.cargo/bin:/usr/local/nvm/versions/node/v${NODE_VERSION}/bin:/opt/java-17/bin:/opt/flutter/bin:/opt/android-sdk/cmdline-tools/latest/bin:/opt/android-sdk/platform-tools:\$PATH"
EOF

version=$(curl -fsSL https://api.github.com/repos/actions/runner/releases/latest | jq -r .tag_name)
version=${version#v}
run_home=/home/runner/actions-runner
mkdir -p "$run_home"
curl -fsSL "https://github.com/actions/runner/releases/download/v${version}/actions-runner-linux-x64-${version}.tar.gz" \
  | tar -xz -C "$run_home"
"$run_home/bin/installdependencies.sh"

# env.sh keeps an existing .env and only appends what is missing, so these reach every job, including the variables
# env.sh does not copy itself.
cat >"$run_home/.env" <<'EOF'
LANG=C.UTF-8
NVM_DIR=/usr/local/nvm
RUNNER_TOOL_CACHE=/opt/hostedtoolcache
AGENT_TOOLSDIRECTORY=/opt/hostedtoolcache
ANDROID_HOME=/opt/android-sdk
ANDROID_SDK_ROOT=/opt/android-sdk
JAVA_HOME=/opt/java-17
EOF
chown -R runner:runner /home/runner
