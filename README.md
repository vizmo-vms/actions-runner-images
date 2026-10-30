# actions-runner-images

Runner images for vizmo-vms CI.

## Azure runner images

[`azure/`](azure) builds the VM images for the GARM runners on Azure Spot (`small`, `medium`, `large`): the tools
below plus the tool cache, Android SDK, Flutter, Playwright, Rust and the pre-pulled CI images. See
[`azure/README.md`](azure/README.md).

[`retry-evicted.yml`](.github/workflows/retry-evicted.yml) is a reusable workflow that re-runs jobs a Spot eviction
cut short. Each repository that uses the Azure runners calls it from a `workflow_run` workflow.

## ARC image (until ARC is removed)

The [`Dockerfile`](Dockerfile) derives from `ghcr.io/actions/actions-runner:latest` for ARC runners that start
`dockerd` under sysbox. It includes:

- Node.js 24.22.1 through nvm 0.40.8 (`NVM_DIR=/usr/local/nvm`)
- pnpm 11.0.0
- Temporal CLI 1.9.1
- DevSpace 6.3.21, Rancher CLI 2.9.5, and kubectl 1.35.9
- Docker Compose 5.6.0
- `build-essential`, Python 3, `pkg-config`, and the Cairo, Pango, JPEG, GIF, and SVG development libraries for node-canvas
- `jq`, Git, curl, CA certificates, unzip, zip, and xz
- `iptables` and `iproute2` for Sysbox dockerd networking

Node and pnpm are on `PATH` by default. Workflows can also source `$NVM_DIR/nvm.sh` and select Node 24, as the platform E2E workflow does.

Published image:

```text
ghcr.io/vizmo-vms/actions-runner-sysbox:latest
```

The build verifies the tools as the unprivileged `runner` user before publishing. Dependencies are installed at image build time, so runner startup and E2E setup do not need `apt-get update`.

The official ARC base, `runner` user, and bundled Docker engine are retained. There is no DinD sidecar; the existing ARC pod configuration starts dockerd inside Sysbox.
