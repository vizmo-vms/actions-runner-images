FROM ghcr.io/actions/actions-runner:latest

LABEL org.opencontainers.image.source="https://github.com/vizmo-vms/actions-runner-sysbox"
LABEL org.opencontainers.image.description="GitHub Actions runner image with sysbox dockerd network tools"

USER root

RUN apt-get update \
    && apt-get install -y --no-install-recommends iptables iproute2 \
    && rm -rf /var/lib/apt/lists/*

USER runner
