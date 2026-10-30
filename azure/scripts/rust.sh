#!/usr/bin/env bash
# Stable Rust for the runner user; secure-plan's CI bootstraps rustup only when it is missing.
set -euo pipefail

runuser -l runner -s /bin/bash -c \
  "curl -fsSL https://sh.rustup.rs | sh -s -- -y --no-modify-path --profile minimal --component clippy,rustfmt"
