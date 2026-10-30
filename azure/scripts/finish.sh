#!/usr/bin/env bash
# Trims the build VM down to what the image needs and checks it fits its disk budget. Packer then deprovisions and
# captures it.
#
# Usage: finish.sh base|large
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)

# Used space each flavor may take, so jobs keep at least 12 GB free on a 32 GB disk (base) and 25 GB on 64 GB (large).
case "$1" in
  base) budget_gb=19 ;;
  large) budget_gb=37 ;;
esac

mkdir -p /etc/runner-image
install -m 0644 "$here/versions.env" /etc/runner-image/versions.env
install -m 0755 "$here/../files/runner-image-check" /usr/local/bin/runner-image-check

docker builder prune --all --force >/dev/null
apt-get clean
rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/* /root/.cache /home/runner/.cache/pip
journalctl --vacuum-time=1s >/dev/null 2>&1 || true

runner-image-check "$budget_gb"

# Discarded blocks are left out of the gallery snapshot, so VMs read less while their disk hydrates.
fstrim -av || true
