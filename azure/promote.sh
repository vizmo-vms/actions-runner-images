#!/usr/bin/env bash
# Boot-tests freshly built gallery versions, makes them the latest (GARM scale sets reference the image definitions,
# so new runners pick them up), and keeps only the newest three promoted versions of each image.
#
# Usage: promote.sh <version> [flavor...]   flavors default to "base large"; needs an az login with Contributor on
#                                           the resource group
set -euo pipefail

version=$1
shift
flavors=("$@")
[ "${#flavors[@]}" -gt 0 ] || flavors=(base large)
rg=${RESOURCE_GROUP:-rg-runner-images}
gallery=${GALLERY:-vizmo_runners}
location=newzealandnorth
keep=3
subscription=$(az account show --query id -o tsv)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
ssh-keygen -q -t ed25519 -N '' -f "$work/key"

az network vnet show -g "$rg" -n vnet-image-test -o none 2>/dev/null \
  || az network vnet create -g "$rg" -n vnet-image-test -l "$location" --address-prefixes 10.90.0.0/24 \
    --subnet-name default --subnet-prefixes 10.90.0.0/24 -o none

# Boots a VM the way GARM does (Premium SSD, admin user "runner", no public IP) and runs runner-image-check. It is not
# Spot, so a capacity shortage or an eviction can't fail a good image; both flavors fit the 10-vCPU regular quota.
boot_test() {
  local flavor=$1 disk_gb=$2
  local vm="image-test-${flavor}-${version//./-}"
  local status=0
  : >"$work/$flavor.log"
  az vm create -g "$rg" -n "$vm" -l "$location" \
    --image "/subscriptions/$subscription/resourceGroups/$rg/providers/Microsoft.Compute/galleries/$gallery/images/runner-$flavor/versions/$version" \
    --size Standard_F2ams_v6 \
    --os-disk-size-gb "$disk_gb" --storage-sku Premium_LRS --security-type Standard \
    --vnet-name vnet-image-test --subnet default --public-ip-address "" --nsg "" \
    --admin-username runner --ssh-key-values "$work/key.pub" \
    --nic-delete-option Delete --os-disk-delete-option Delete -o none || status=$?
  if [ "$status" -eq 0 ]; then
    timeout 20m az vm run-command invoke -g "$rg" -n "$vm" --command-id RunShellScript \
      --scripts "cloud-init status --wait >/dev/null; runner-image-check" --query "value[0].message" -o tsv \
      >"$work/$flavor.log" || status=$?
  fi
  # Also after a failed create, which can leave a VM in the Failed state.
  az vm delete -g "$rg" -n "$vm" --yes --no-wait 2>/dev/null || true
  cat "$work/$flavor.log"
  [ "$status" -eq 0 ] && grep -q "runner-image-check: PASS" "$work/$flavor.log"
}

pids=()
for flavor in "${flavors[@]}"; do
  case "$flavor" in
    base) disk_gb=32 ;;
    large) disk_gb=64 ;;
    *)
      echo "unknown flavor: $flavor" >&2
      exit 2
      ;;
  esac
  boot_test "$flavor" "$disk_gb" >"$work/$flavor.out" 2>&1 &
  pids+=($!)
done
failed=0
for i in "${!flavors[@]}"; do
  if wait "${pids[$i]}"; then
    echo "::group::runner-${flavors[$i]} $version boot test passed"
  else
    echo "::group::runner-${flavors[$i]} $version boot test FAILED"
    failed=1
  fi
  cat "$work/${flavors[$i]}.out"
  echo "::endgroup::"
done
if [ "$failed" -ne 0 ]; then
  echo "Leaving $version hidden from latest." >&2
  exit 1
fi

for flavor in "${flavors[@]}"; do
  az sig image-version update -g "$rg" -r "$gallery" -i "runner-$flavor" -e "$version" \
    --set publishingProfile.excludeFromLatest=false -o none
  echo "runner-$flavor $version is now the latest"
  versions=$(az sig image-version list -g "$rg" -r "$gallery" -i "runner-$flavor" \
    --query "[].[name, publishingProfile.excludeFromLatest]" -o tsv)
  # Hidden versions failed their boot test or were rolled back. Only promoted ones count towards the rollback history,
  # so a run of failed builds can't push the last good version out.
  stale=$(awk '$2 == "True" { print $1 }' <<<"$versions"
    awk '$2 == "False" { print $1 }' <<<"$versions" | sort -rV | tail -n +$((keep + 1)))
  for old in $stale; do
    echo "deleting runner-$flavor $old"
    az sig image-version delete -g "$rg" -r "$gallery" -i "runner-$flavor" -e "$old" --no-wait
  done
done
