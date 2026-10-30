#!/usr/bin/env bash
# Runs as the runner user: accepts the SDK licenses, precaches Flutter's Android artifacts, and builds a throwaway app
# with the Gradle, AGP, Kotlin and compileSdk of the kiosk and mobile apps, so Gradle, its plugins, build-tools and the
# NDK are already in the runner's caches.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
. "$here/versions.env"

yes | sdkmanager --licenses >/dev/null || true
sdkmanager --install platform-tools "platforms;${ANDROID_PLATFORM}"
git config --global --add safe.directory '*'
flutter config --no-analytics --no-cli-animations --android-sdk "$ANDROID_HOME"
dart --disable-analytics
flutter precache --android
yes | flutter doctor --android-licenses >/dev/null || true

work=$(mktemp -d)
cd "$work"
flutter create --platforms android --org in.vizmo.warmup warmup >/dev/null
cd warmup/android
sed -i "s#^distributionUrl=.*#distributionUrl=https\\\\://services.gradle.org/distributions/gradle-${GRADLE_VERSION}-bin.zip#" \
  gradle/wrapper/gradle-wrapper.properties
for f in settings.gradle settings.gradle.kts; do
  [ -f "$f" ] || continue
  sed -i -E \
    -e "s/(com\.android\.application\"\)? version )\"[^\"]+\"/\1\"${AGP_VERSION}\"/" \
    -e "s/(org\.jetbrains\.kotlin\.android\"\)? version )\"[^\"]+\"/\1\"${KOTLIN_VERSION}\"/" "$f"
done
for f in app/build.gradle app/build.gradle.kts; do
  [ -f "$f" ] || continue
  sed -i -E "s/compileSdk( =)? flutter\.compileSdkVersion/compileSdk = ${ANDROID_COMPILE_SDK}/" "$f"
done
grep -h -E "distributionUrl|com.android.application|kotlin.android|compileSdk" \
  gradle/wrapper/gradle-wrapper.properties settings.gradle* app/build.gradle* || true
cd ..
# Best effort: if the template stops building with these versions, most downloads have still happened.
flutter build apk --debug || echo "::warning::warm-up debug build failed; Gradle caches are only partly filled"
flutter build apk --release || echo "::warning::warm-up release build failed"
cd /
rm -rf "$work"
pkill -u "$(id -u)" -f GradleDaemon || true
