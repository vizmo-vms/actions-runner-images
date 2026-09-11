# actions-runner-sysbox

Derivative of `ghcr.io/actions/actions-runner:latest` for ARC runners that start `dockerd` under sysbox.

Adds:

- `iptables`
- `iproute2`

Published image:

```text
ghcr.io/vizmo-vms/actions-runner-sysbox:latest
```

This removes runtime `apt-get update` from ARC runner startup.
