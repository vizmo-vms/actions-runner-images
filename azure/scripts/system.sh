#!/usr/bin/env bash
# System packages, Docker, and the CLIs jobs expect on PATH. Jobs never install these themselves.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
. "$here/versions.env"
export DEBIAN_FRONTEND=noninteractive

# The first boot's own apt run holds the lock until cloud-init finishes.
cloud-init status --wait >/dev/null || true

install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg -o /etc/apt/keyrings/githubcli.gpg
chmod a+r /etc/apt/keyrings/docker.asc /etc/apt/keyrings/githubcli.gpg
. /etc/os-release
echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu ${VERSION_CODENAME} stable" \
  >/etc/apt/sources.list.d/docker.list
echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/githubcli.gpg] https://cli.github.com/packages stable main" \
  >/etc/apt/sources.list.d/github-cli.list

apt-get update -q
apt-get dist-upgrade -y -q
# First group: the ARC image (the Dockerfile in this repository). Second: packages jobs apt-get install
# today (flutter, secure-plan, argus, platform). Third: native-gem, Flutter test and general build tooling.
apt-get install -y -q --no-install-recommends \
  build-essential ca-certificates curl git iptables iproute2 jq libcairo2-dev libgif-dev libjpeg-dev \
  libpango1.0-dev librsvg2-dev pkg-config python3 unzip xz-utils zip \
  acl python3-pip python3-venv ripgrep wget \
  libgl1-mesa-dev libx11-dev libxcursor-dev libxi-dev libxrandr-dev libxkbcommon-dev libxkbcommon-x11-0 \
  libwayland-dev libfontconfig1-dev libfreetype6-dev xvfb xauth mesa-vulkan-drivers libvulkan1 \
  libffi-dev libssl-dev libyaml-dev zlib1g-dev libglu1-mesa file git-lfs gnupg lsb-release openssh-client \
  rsync time tree zstd \
  docker-ce docker-ce-cli containerd.io docker-buildx-plugin gh

install -m 0644 "$here/../files/daemon.json" /etc/docker/daemon.json
systemctl enable docker.service containerd.service
systemctl restart docker.service

curl -fsSL https://temporal.download/cli.sh | sh -s -- --dir /usr/local/temporal --version "${TEMPORAL_CLI_VERSION}"
ln -sf /usr/local/temporal/bin/temporal /usr/local/bin/temporal

curl -fsSL -o /usr/local/bin/devspace \
  "https://github.com/devspace-sh/devspace/releases/download/${DEVSPACE_VERSION}/devspace-linux-amd64"
# Only the binary: the tarball's "./" entry would reset the mode of whatever directory it is unpacked into.
curl -fsSL "https://releases.rancher.com/cli2/${RANCHER_CLI_VERSION}/rancher-linux-amd64-${RANCHER_CLI_VERSION}.tar.gz" \
  | tar -xzO "./rancher-${RANCHER_CLI_VERSION}/rancher" >/usr/local/bin/rancher
curl -fsSL -o /usr/local/bin/kubectl "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl"
curl -fsSL -o /usr/local/bin/yq https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64
chmod 0755 /usr/local/bin/devspace /usr/local/bin/rancher /usr/local/bin/kubectl /usr/local/bin/yq

# Pinned Compose, ahead of any packaged plugin on the CLI's plugin path.
mkdir -p /usr/local/lib/docker/cli-plugins
curl -fsSL -o /usr/local/lib/docker/cli-plugins/docker-compose \
  "https://github.com/docker/compose/releases/download/${DOCKER_COMPOSE_VERSION}/docker-compose-linux-x86_64"
chmod 0755 /usr/local/lib/docker/cli-plugins/docker-compose

install -m 0755 "$here/../files/garm-preempt-watch" /usr/local/bin/garm-preempt-watch
install -m 0644 "$here/../files/garm-preempt-watch.service" /etc/systemd/system/garm-preempt-watch.service
systemctl daemon-reload
systemctl enable garm-preempt-watch.service

# A runner lives for one job: background apt runs would only hold the dpkg lock and compete with it.
systemctl disable apt-daily.timer apt-daily-upgrade.timer
apt-get purge -y -q unattended-upgrades
