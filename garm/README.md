# GARM runners on Azure Spot

The GARM scale sets for vizmo-vms boot stock Ubuntu 24.04 on Azure Spot VMs in New Zealand North. There is no custom
image: [`bootstrap.sh`](bootstrap.sh) runs on every VM before GARM installs the runner, and installs what jobs expect:

- The ARC image's tools at the same versions: nvm with Node 24.22.1 and pnpm 11.0.0 (`NVM_DIR=/usr/local/nvm`),
  Temporal CLI, DevSpace, Rancher CLI, kubectl and Docker Compose, plus the build and node-canvas packages
- Docker (Docker Hub pulls go through `mirror.gcr.io`), gh, yq, and the packages jobs used to `apt-get install`
  themselves
- `NVM_DIR`, `RUNNER_TOOL_CACHE` and `AGENT_TOOLSDIRECTORY=/opt/hostedtoolcache` in every job's environment, and Node 24
  on `PATH`
- `garm-preempt-watch`, which stops the runner as soon as Azure announces a Spot eviction, so the job fails at once
  instead of after GitHub's 10-minute lost-runner timeout. Callers of
  [`retry-evicted.yml`](../.github/workflows/retry-evicted.yml) then re-run it.

The script logs to `/var/log/runner-bootstrap.log`. If any step fails, the VM powers off without registering, and GARM
replaces it once the bootstrap timeout passes.

## Scale sets

Organization `vizmo-vms`, provider `azure`, runner group `Default`, min idle 0. The scale set name is also a runner
label, so it matches the size label jobs use.

| Name | Labels | Flavor | Max | Disk GB |
| --- | --- | --- | --- | --- |
| `small` | `self-hosted`, `small` | `Standard_F2ams_v6` | 20 | 32 |
| `medium` | `self-hosted`, `medium` | `Standard_F4ams_v6` | 28 | 32 |
| `large` | `self-hosted`, `large` | `Standard_F8ams_v6` | 12 | 64 |

Image `Canonical:ubuntu-24_04-lts:server:latest`. Since October 2026 it boots the `7.0.0-*-azure` kernel.

MongoDB 8.0 refuses to start on Linux 6.19 and newer ("Linux kernel versions 6.19 and newer has a known
incompatibility", [SERVER-121912](https://jira.mongodb.org/browse/SERVER-121912)), Ubuntu's 7.0 kernels included: they
carry the upstream fix, but the check ignores Ubuntu's patch level
([SERVER-136848](https://jira.mongodb.org/browse/SERVER-136848)). The check only applies while glibc's rseq is off,
which the Percona image sets (`GLIBC_TUNABLES=glibc.pthread.rseq=0`). A job that starts MongoDB 8 sets
`GLIBC_TUNABLES=glibc.pthread.rseq=1` on the mongod container, as platform's dev stack does
([platform#345](https://github.com/vizmo-vms/platform/pull/345)).

If a new image breaks jobs, pin a known-good version (`Canonical:ubuntu-24_04-lts:server:24.04.<version>`). Check it
with `az vm image show --location newzealandnorth --urn <image>` first: some listed versions do not resolve (for
example 24.04.202607280 and 24.04.202610090), and GARM then retries the VM creation without end.

Extra specs (`disk_size_gb` 64 for `large`):

```json
{
  "spot": true,
  "storage_account_type": "Premium_LRS",
  "disk_size_gb": 32,
  "allocate_public_ip": false,
  "disable_updates": true,
  "pre_install_scripts": {"bootstrap": "<base64 of bootstrap.sh>"},
  "extra_tags": {"purpose": "github-runner"}
}
```

`disable_updates` stops GARM's cloud-config from upgrading every package on each boot. After changing
`bootstrap.sh`, put the new version into each scale set's extra specs:

```bash
base64 -w0 garm/bootstrap.sh   # macOS: base64 -i garm/bootstrap.sh
```

Existing idle runners keep the old version until they are replaced.
