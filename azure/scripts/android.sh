#!/usr/bin/env bash
# Android SDK and Flutter for the vizmo-vms/flutter Android builds. android-warmup.sh then fills the runner's Gradle
# and SDK caches.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
. "$here/versions.env"

sdk=/opt/android-sdk
tools=$(curl -fsSL https://dl.google.com/android/repository/repository2-3.xml \
  | grep -oE 'commandlinetools-linux-[0-9]+_latest\.zip' | sort -V | tail -1)
mkdir -p "$sdk/cmdline-tools"
curl -fsSL -o /tmp/cmdline-tools.zip "https://dl.google.com/android/repository/${tools}"
unzip -q /tmp/cmdline-tools.zip -d "$sdk/cmdline-tools"
mv "$sdk/cmdline-tools/cmdline-tools" "$sdk/cmdline-tools/latest"
rm /tmp/cmdline-tools.zip

# Flutter where subosito/flutter-action looks before downloading (tool cache, channel-version-arch), linked from a
# stable path for PATH.
flutter_home="/opt/hostedtoolcache/flutter/stable-${FLUTTER_VERSION}-x64"
mkdir -p "$(dirname "$flutter_home")"
curl -fsSL "https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_${FLUTTER_VERSION}-stable.tar.xz" \
  | tar -xJ -C /tmp
mv /tmp/flutter "$flutter_home"
ln -sfn "$flutter_home" /opt/flutter
chown -R runner:runner "$sdk" "$flutter_home"

runuser -l runner -s /bin/bash -c "bash '$here/android-warmup.sh'"
