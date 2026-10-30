#!/usr/bin/env bash
# Deletes what a cancelled or failed image build left running: Packer's temporary build VM (tagged
# purpose=github-runner-image-build) and promote.sh's boot-test VMs (image-test-*), with their NICs and disks.
#
# Usage: cleanup.sh   needs an az login with Contributor on the resource group
set -euo pipefail

rg=${RESOURCE_GROUP:-rg-runner-images}
leftover="[?tags.purpose=='github-runner-image-build' || starts_with(name, 'image-test-')].id"

# VMs first: a NIC or disk can't be deleted while a VM still uses it.
for type in Microsoft.Compute/virtualMachines Microsoft.Network/networkInterfaces Microsoft.Compute/disks \
    Microsoft.Network/publicIPAddresses; do
  ids=$(az resource list -g "$rg" --resource-type "$type" --query "$leftover" -o tsv)
  [ -n "$ids" ] || continue
  echo "deleting $ids"
  az resource delete --ids $ids -o none
done
