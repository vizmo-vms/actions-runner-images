FROM ghcr.io/actions/actions-runner:latest

LABEL org.opencontainers.image.source="https://github.com/vizmo-vms/actions-runner-sysbox"
LABEL org.opencontainers.image.description="GitHub Actions runner image with Sysbox and vizmo-vms workflow dependencies"

ARG NVM_VERSION=v0.40.8
ARG NODE_VERSION=24.21.0
ARG PNPM_VERSION=11.0.0
ARG TEMPORAL_CLI_VERSION=1.9.1
ARG DEVSPACE_VERSION=v6.3.21
ARG RANCHER_CLI_VERSION=v2.9.5
ARG KUBECTL_VERSION=v1.35.9
ARG DOCKER_COMPOSE_VERSION=v5.6.0

USER root

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        build-essential \
        ca-certificates \
        curl \
        git \
        iptables \
        iproute2 \
        jq \
        libcairo2-dev \
        libgif-dev \
        libjpeg-dev \
        libpango1.0-dev \
        librsvg2-dev \
        pkg-config \
        python3 \
        unzip \
        xz-utils \
        zip \
    && rm -rf /var/lib/apt/lists/*

ENV NVM_DIR=/usr/local/nvm
RUN mkdir -p "${NVM_DIR}" \
    && curl -fsSL "https://raw.githubusercontent.com/nvm-sh/nvm/${NVM_VERSION}/install.sh" | PROFILE=/dev/null bash \
    && . "${NVM_DIR}/nvm.sh" \
    && nvm install "${NODE_VERSION}" \
    && nvm alias default "${NODE_VERSION}" \
    && npm install --global "pnpm@${PNPM_VERSION}" \
    && nvm cache clear
ENV PATH="${NVM_DIR}/versions/node/v${NODE_VERSION}/bin:${PATH}"

RUN curl -fsSL https://temporal.download/cli.sh | sh -s -- --dir /usr/local/temporal --version "${TEMPORAL_CLI_VERSION}" \
    && ln -s /usr/local/temporal/bin/temporal /usr/local/bin/temporal

RUN curl -fsSL -o /usr/local/bin/devspace \
        "https://github.com/devspace-sh/devspace/releases/download/${DEVSPACE_VERSION}/devspace-linux-amd64" \
    && chmod 0755 /usr/local/bin/devspace \
    && curl -fsSL "https://releases.rancher.com/cli2/${RANCHER_CLI_VERSION}/rancher-linux-amd64-${RANCHER_CLI_VERSION}.tar.gz" \
        | tar -xz --no-same-owner --no-overwrite-dir -C /tmp \
    && install -m 0755 "/tmp/rancher-${RANCHER_CLI_VERSION}/rancher" /usr/local/bin/rancher \
    && rm -rf "/tmp/rancher-${RANCHER_CLI_VERSION}" \
    && curl -fsSL -o /usr/local/bin/kubectl \
        "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl" \
    && chmod 0755 /usr/local/bin/kubectl \
    && mkdir -p /usr/local/lib/docker/cli-plugins \
    && curl -fsSL -o /usr/local/lib/docker/cli-plugins/docker-compose \
        "https://github.com/docker/compose/releases/download/${DOCKER_COMPOSE_VERSION}/docker-compose-linux-x86_64" \
    && chmod 0755 /usr/local/lib/docker/cli-plugins/docker-compose \
    && chmod 1777 /tmp

USER runner

# Verify the same nvm selection and tools used by E2E before the image is published.
RUN . "${NVM_DIR}/nvm.sh" \
    && nvm use "${NODE_VERSION%%.*}" \
    && test "$(node --version)" = "v${NODE_VERSION}" \
    && test "$(pnpm --version)" = "${PNPM_VERSION}" \
    && temporal --version \
    && devspace version \
    && rancher --version \
    && kubectl version --client \
    && test "$(docker compose version --short)" = "${DOCKER_COMPOSE_VERSION#v}" \
    && dpkg -s build-essential libcairo2-dev libpango1.0-dev libjpeg-dev libgif-dev librsvg2-dev >/dev/null \
    && test "$(stat -c %a /tmp)" = 1777
