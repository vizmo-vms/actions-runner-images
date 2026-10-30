# Azure runner images

VM images for the GARM runners on Azure Spot (New Zealand North). GARM starts one VM per job from these images; the
VM boots with every tool already installed, so cloud-init only registers the runner. No apt, downloads or pulls happen
at boot, as long as the scale set's extra specs set `"disable_updates": true` (otherwise GARM's cloud-config upgrades
every package first). The apt timers and unattended-upgrades are off, and the tool cache belongs to the runner user,
so `setup-*` actions can still add versions it lacks.

| Image | Runners | VM disk | Adds |
| --- | --- | --- | --- |
| `runner-base` | `small`, `medium` | 32 GB Premium SSD | Everything below |
| `runner-large` | `large` | 64 GB Premium SSD | The images in [`images-large.txt`](images-large.txt), pre-pulled, and Playwright Chromium for argus (1.61.1) |

`runner-base` contains:

- Docker Engine with Buildx and Compose 5.6.0, `mirror.gcr.io` as the Docker Hub mirror, and the runner user in the
  `docker` group
- What the ARC image has: nvm with Node 24.22.1 and pnpm 11.0.0 (`NVM_DIR=/usr/local/nvm`), Temporal CLI, DevSpace,
  Rancher CLI, kubectl, and the build and canvas libraries
- The packages jobs used to `apt-get install` themselves (secure-plan's GUI and Vulkan libraries, xvfb, ripgrep, acl,
  python3-venv), plus gh, yq and git-lfs
- A tool cache at `/opt/hostedtoolcache` that `actions/setup-node`, `setup-python`, `setup-java`, `ruby/setup-ruby`
  and `subosito/flutter-action` use without downloading: Node 24.22.1 and 24.21.0, Python 3.11, Ruby 3.3, Temurin 17,
  Flutter 3.47.6
- The Android SDK (`platforms;android-37.0`, build-tools and the NDK) and warm Gradle 9.1.0, AGP 9.0.1 and Kotlin
  2.3.20 caches
- Playwright Chromium for 1.63.0, 1.60.0 and 1.52.0, and its system libraries
- Rust stable (rustup, clippy, rustfmt)
- `semgrep/semgrep:latest`, pre-pulled
- The GitHub runner, unpacked in `/home/runner/actions-runner`, and the Spot eviction watcher (`garm-preempt-watch`)

Versions live in [`scripts/versions.env`](scripts/versions.env). `runner-image-check` on any runner VM lists what is
installed and fails on anything missing.

## Build and release

[`azure-image.yml`](../.github/workflows/azure-image.yml) runs nightly, on changes here (other than docs), and on
demand:

1. Packer builds `runner-base` from Ubuntu 24.04, then `runner-large` from that `runner-base`, on a Spot VM. Each
   build fails when the image would leave jobs less than 10 GB (base) or 25 GB (large) of free disk.
2. Both versions go into the `vizmo_runners` gallery in `rg-runner-images`, hidden from "latest".
3. [`promote.sh`](promote.sh) boots each on a fresh VM the way GARM does and runs `runner-image-check`. Only when both
   pass do they become the latest. If `runner-large` fails to build, `runner-base` still goes out and the run fails.
4. Hidden versions are deleted, and the three newest promoted versions of each image are kept for rollback.
5. A failed or cancelled run deletes any build or boot-test VM it left behind ([`cleanup.sh`](cleanup.sh)).

The workflow signs in to Azure as the `id-runner-image-builder` managed identity (OIDC, Contributor on
`rg-runner-images` only). Repository variables `AZURE_CLIENT_ID`, `AZURE_TENANT_ID` and `AZURE_SUBSCRIPTION_ID` name
it. Every pre-pulled image is public, so the build needs no registry credentials, and the GitHub side is a free
`ubuntu-latest` runner that only drives Packer; the image itself builds on a temporary Spot VM in `rg-runner-images`.

GARM's scale sets use the image definitions, not a version, so a promoted version reaches new runners without touching
GARM. To roll back, hide the bad version:

```bash
az sig image-version update -g rg-runner-images -r vizmo_runners -i runner-base -e <version> \
  --set publishingProfile.excludeFromLatest=true
```

To try a change before merging it, build locally with your own `az login`. The version lands in the gallery hidden,
so runners never use it, and the next promote deletes it. `runner-large` needs the `runner-base` version to build on:

```bash
packer init azure
packer build -var flavor=base -var image_version=0.$(date -u +%Y%m%d).1 -var subscription_id=<subscription> azure
packer build -var flavor=large -var base_version=0.$(date -u +%Y%m%d).1 -var image_version=0.$(date -u +%Y%m%d).1 \
  -var subscription_id=<subscription> azure
```

## Adding a tool

Add it to the matching script in [`scripts/`](scripts), pin its version in `versions.env` when jobs check for an exact
version, and add a line to [`files/runner-image-check`](files/runner-image-check). For an image that jobs start, add
the exact reference (tag and digest as the compose file or Dockerfile has it) to `images-base.txt` or
`images-large.txt`.
