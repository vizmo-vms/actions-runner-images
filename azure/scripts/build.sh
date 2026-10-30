#!/usr/bin/env bash
# Runs as root on the Packer build VM: installs one image flavor, cleans up and checks the result.
#
# Usage: build.sh base|large
#   base   everything jobs need (small and medium runners); starts from Ubuntu
#   large  pre-pulls the images large jobs start; starts from the runner-base version built in the same run
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
flavor=$1

step() {
  echo "::: $1"
  bash "$here/$1.sh" "${@:2}"
}

case "$flavor" in
  base)
    for name in system runner node toolcache android playwright rust; do
      step "$name"
    done
    step images "$here/../images-base.txt"
    ;;
  large)
    step images "$here/../images-large.txt"
    ;;
  *)
    echo "unknown flavor: $flavor" >&2
    exit 1
    ;;
esac

step finish "$flavor"
