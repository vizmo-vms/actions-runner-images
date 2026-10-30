#!/usr/bin/env bash
# Installs what jobs expect on a stock Ubuntu 24.04 VM, before GARM installs and registers the runner. GARM runs it as
# root from cloud-init (extra spec `pre_install_scripts`), so it must not wait for cloud-init and must not create
# /home/runner/actions-runner (GARM skips the runner download when that directory exists).
#
# A VM that fails here powers off without registering; GARM replaces it once the bootstrap timeout passes.
set -Eeuo pipefail

# Keep in step with the ARC image (the Dockerfile in this repository) until ARC is retired.
NVM_VERSION=v0.40.8
NODE_VERSION=24.22.1
PNPM_VERSION=11.0.0
TEMPORAL_CLI_VERSION=1.9.1
DEVSPACE_VERSION=v6.3.21
RANCHER_CLI_VERSION=v2.9.5
KUBECTL_VERSION=v1.35.9
DOCKER_COMPOSE_VERSION=v5.6.0

export DEBIAN_FRONTEND=noninteractive
export NVM_DIR=/usr/local/nvm
NODE_BIN="$NVM_DIR/versions/node/v${NODE_VERSION}/bin"
TOOL_CACHE=/opt/hostedtoolcache

exec > >(tee -a /var/log/runner-bootstrap.log) 2>&1
phase() { echo "bootstrap: ${SECONDS}s $*"; }
fail() {
  phase "FAILED: $*"
  systemctl poweroff
  exit 1
}
trap 'fail "line $LINENO"' ERR
fetch() { curl -fsSL --retry 5 --retry-all-errors --retry-delay 2 "$@"; }
retry() {
  local attempt
  for attempt in 1 2 3 4; do
    "$@" && return 0
    sleep $((attempt * 5))
  done
  "$@"
}

phase "start"

# A runner lives for one job: background apt runs would only hold the dpkg lock and compete with it.
systemctl disable --now apt-daily.timer apt-daily-upgrade.timer
systemctl stop apt-daily.service apt-daily-upgrade.service unattended-upgrades.service || true

# Skip the work dpkg does for a long-lived machine: fsync after every file, man pages and docs, the man-db index.
echo force-unsafe-io >/etc/dpkg/dpkg.cfg.d/runner-unsafe-io
cat >/etc/dpkg/dpkg.cfg.d/runner-excludes <<'EOF'
path-exclude=/usr/share/doc/*
path-include=/usr/share/doc/*/copyright
path-exclude=/usr/share/man/*
EOF
rm -f /var/lib/man-db/auto-update

install_clis() {
  fetch https://temporal.download/cli.sh | sh -s -- --dir /usr/local/temporal --version "${TEMPORAL_CLI_VERSION}"
  ln -sf /usr/local/temporal/bin/temporal /usr/local/bin/temporal
  fetch -o /usr/local/bin/devspace \
    "https://github.com/devspace-sh/devspace/releases/download/${DEVSPACE_VERSION}/devspace-linux-amd64"
  # Only the binary: the tarball's "./" entry would reset the mode of whatever directory it is unpacked into.
  fetch "https://releases.rancher.com/cli2/${RANCHER_CLI_VERSION}/rancher-linux-amd64-${RANCHER_CLI_VERSION}.tar.gz" \
    | tar -xzO "./rancher-${RANCHER_CLI_VERSION}/rancher" >/usr/local/bin/rancher
  fetch -o /usr/local/bin/kubectl "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl"
  fetch -o /usr/local/bin/yq https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64
  chmod 0755 /usr/local/bin/devspace /usr/local/bin/rancher /usr/local/bin/kubectl /usr/local/bin/yq
  # Pinned Compose, ahead of the packaged plugin on the CLI's plugin path.
  mkdir -p /usr/local/lib/docker/cli-plugins
  fetch -o /usr/local/lib/docker/cli-plugins/docker-compose \
    "https://github.com/docker/compose/releases/download/${DOCKER_COMPOSE_VERSION}/docker-compose-linux-x86_64"
  chmod 0755 /usr/local/lib/docker/cli-plugins/docker-compose
}

install_node() {
  mkdir -p "$NVM_DIR"
  fetch "https://raw.githubusercontent.com/nvm-sh/nvm/${NVM_VERSION}/install.sh" | PROFILE=/dev/null bash
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
}

# Downloads run beside apt; each logs to its own file so the output does not interleave.
(trap - ERR; install_clis) >/var/log/runner-bootstrap-clis.log 2>&1 &
clis_pid=$!
(trap - ERR; install_node) >/var/log/runner-bootstrap-node.log 2>&1 &
node_pid=$!

phase "apt"
install -m 0755 -d /etc/apt/keyrings
fetch -o /etc/apt/keyrings/docker.asc https://download.docker.com/linux/ubuntu/gpg
fetch -o /etc/apt/keyrings/githubcli.gpg https://cli.github.com/packages/githubcli-archive-keyring.gpg
chmod a+r /etc/apt/keyrings/docker.asc /etc/apt/keyrings/githubcli.gpg
. /etc/os-release
echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu ${VERSION_CODENAME} stable" \
  >/etc/apt/sources.list.d/docker.list
echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/githubcli.gpg] https://cli.github.com/packages stable main" \
  >/etc/apt/sources.list.d/github-cli.list

# Docker reads this when the package starts it: Docker Hub pulls go through Google's mirror, and logs stay bounded.
mkdir -p /etc/docker
cat >/etc/docker/daemon.json <<'EOF'
{
  "features": {"containerd-snapshotter": false},
  "registry-mirrors": ["https://mirror.gcr.io"],
  "log-driver": "json-file",
  "log-opts": {"max-size": "50m", "max-file": "2"}
}
EOF

apt_get() { apt-get -q -o DPkg::Lock::Timeout=300 -o Acquire::Retries=5 "$@"; }
retry apt_get update
# First group: the ARC image. Second: packages jobs apt-get install today (flutter, secure-plan, argus, platform).
# Third: native-gem, Flutter test and general build tooling.
retry apt_get install -y --no-install-recommends \
  build-essential ca-certificates curl git iptables iproute2 jq libcairo2-dev libgif-dev libjpeg-dev \
  libpango1.0-dev librsvg2-dev pkg-config python3 unzip xz-utils zip \
  acl python3-pip python3-venv ripgrep wget \
  libgl1-mesa-dev libx11-dev libxcursor-dev libxi-dev libxrandr-dev libxkbcommon-dev libxkbcommon-x11-0 \
  libwayland-dev libfontconfig1-dev libfreetype6-dev xvfb xauth mesa-vulkan-drivers libvulkan1 \
  libffi-dev libssl-dev libyaml-dev zlib1g-dev libglu1-mesa file git-lfs gnupg lsb-release openssh-client \
  rsync time tree zstd \
  docker-ce docker-ce-cli containerd.io docker-buildx-plugin gh
usermod -aG docker runner

phase "waiting for downloads"
wait "$clis_pid" || { cat /var/log/runner-bootstrap-clis.log; fail "installing the CLIs"; }
wait "$node_pid" || { cat /var/log/runner-bootstrap-node.log; fail "installing Node"; }

phase "runner environment"
install -d -o runner -g runner "$TOOL_CACHE"
# Login shells (GARM runs the runner install with `su -l`) pick these up, and the runner's env.sh copies PATH into
# .path, which becomes every job's PATH.
cat >/etc/profile.d/runner-env.sh <<EOF
export NVM_DIR=$NVM_DIR
export RUNNER_TOOL_CACHE=$TOOL_CACHE
export AGENT_TOOLSDIRECTORY=$TOOL_CACHE
export PATH="$NODE_BIN:\$PATH"
EOF
# env.sh does not copy NVM_DIR or the tool cache into .env, so the runner service gets them from systemd and passes them
# on to jobs. GARM names the service actions.runner.vizmo-vms.<runner>; this drop-in matches it by prefix.
mkdir -p /etc/systemd/system/actions.runner.vizmo-.service.d
cat >/etc/systemd/system/actions.runner.vizmo-.service.d/runner-env.conf <<EOF
[Service]
Environment=NVM_DIR=$NVM_DIR
Environment=RUNNER_TOOL_CACHE=$TOOL_CACHE
Environment=AGENT_TOOLSDIRECTORY=$TOOL_CACHE
EOF

phase "eviction watcher"
cat >/usr/local/bin/garm-preempt-watch <<'EOF'
#!/usr/bin/env python3
"""Stops the GitHub runner as soon as Azure announces a Spot eviction.

Stopping the service makes the runner cancel its job and report it, so the job fails within seconds instead of after
GitHub's 10 minute lost-runner timeout.
"""
import json
import subprocess
import sys
import time
import urllib.request

EVENTS_URL = "http://169.254.169.254/metadata/scheduledevents?api-version=2020-07-01"


def scheduled_events():
    request = urllib.request.Request(EVENTS_URL, headers={"Metadata": "true"})
    # The first request turns Scheduled Events on for the VM and can take up to two minutes to answer.
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
    with opener.open(request, timeout=150) as response:
        return json.load(response).get("Events", [])


while True:
    try:
        preempt = [e for e in scheduled_events() if e.get("EventType") == "Preempt"]
    except Exception as err:  # IMDS can be briefly unavailable; keep polling.
        print(f"reading scheduled events: {err}", flush=True)
        time.sleep(5)
        continue
    if preempt:
        print(f"eviction announced, stopping the runner: {preempt[0]}", flush=True)
        subprocess.run(["systemctl", "stop", "--no-block", "actions.runner.*"], check=False)
        sys.exit(0)
    time.sleep(2)
EOF
chmod 0755 /usr/local/bin/garm-preempt-watch
cat >/etc/systemd/system/garm-preempt-watch.service <<'EOF'
[Unit]
Description=Stop the GitHub runner when Azure announces a Spot eviction
After=network-online.target
Wants=network-online.target

[Service]
ExecStart=/usr/local/bin/garm-preempt-watch
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable --now garm-preempt-watch.service

phase "checks"
# As the runner sees them: a login shell, with the docker group membership added above.
runuser -l runner -c 'set -e
  node --version; pnpm --version
  docker info --format "docker {{.ServerVersion}}"; docker compose version --short
  temporal --version; kubectl version --client; devspace --version; rancher --version
  gh --version | head -1; jq --version; yq --version'

phase "done"
