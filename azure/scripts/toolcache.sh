#!/usr/bin/env bash
# Python, Ruby and Java in the layout actions/setup-python, ruby/setup-ruby and actions/setup-java look up before
# downloading. ruby/setup-ruby's prebuilt Rubies only work from /opt/hostedtoolcache, which is why the runner's tool
# cache lives there instead of under _work.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
. "$here/versions.env"

cache=/opt/hostedtoolcache
work=$(mktemp -d)
. /etc/os-release

# Newest stable build of each series from the manifest actions/setup-python reads.
for series in ${TOOLCACHE_PYTHON_SERIES}; do
  url=$(curl -fsSL https://raw.githubusercontent.com/actions/python-versions/main/versions-manifest.json | python3 -c "
import json, sys
for release in json.load(sys.stdin):
    if release['stable'] and release['version'].startswith('${series}.'):
        for f in release['files']:
            if f['platform'] == 'linux' and f.get('platform_version') == '${VERSION_ID}' and f['arch'] == 'x64':
                print(f['download_url'])
                sys.exit()
")
  mkdir -p "$work/python"
  curl -fsSL "$url" | tar -xz -C "$work/python"
  (cd "$work/python" && RUNNER_TOOL_CACHE=$cache AGENT_TOOLSDIRECTORY=$cache bash ./setup.sh)
  rm -rf "$work/python"
done

# Newest release of each series that ruby/setup-ruby knows about.
for series in ${TOOLCACHE_RUBY_SERIES}; do
  version=$(curl -fsSL https://raw.githubusercontent.com/ruby/setup-ruby/master/ruby-builder-versions.json | python3 -c "
import json, re, sys
versions = [v for v in json.load(sys.stdin)['ruby'] if re.fullmatch(r'${series}\.\d+', v)]
print(max(versions, key=lambda v: int(v.rsplit('.', 1)[1])))
")
  mkdir -p "$cache/Ruby/$version"
  curl -fsSL "https://github.com/ruby/ruby-builder/releases/download/ruby-${version}/ruby-${version}-ubuntu-${VERSION_ID}-x64.tar.gz" \
    | tar -xz -C "$cache/Ruby/$version"
  touch "$cache/Ruby/$version/x64.complete"
done

# Latest Temurin JDK of each major, under the folder name actions/setup-java uses ("+" in the version becomes "-").
for major in ${TOOLCACHE_JAVA_MAJORS}; do
  read -r release link < <(curl -fsSL \
    "https://api.adoptium.net/v3/assets/latest/${major}/hotspot?architecture=x64&image_type=jdk&os=linux&vendor=eclipse" \
    | jq -r '.[0] | "\(.release_name) \(.binary.package.link)"')
  version=${release#jdk-}
  dir="$cache/Java_Temurin-Hotspot_jdk/${version//+/-}/x64"
  mkdir -p "$dir"
  curl -fsSL "$link" | tar -xz --strip-components=1 -C "$dir"
  touch "${dir}.complete"
  ln -sfn "$dir" "/opt/java-${major}"
done

rm -rf "$work"
