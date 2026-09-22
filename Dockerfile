# syntax=docker/dockerfile:1

ARG CODE_SERVER_BASE_IMAGE=ghcr.io/coder/code-server:latest
ARG UV_VERSION=latest
ARG NODE_VERSION=24

# Keep Node.js independent from the distro version bundled in code-server.
FROM node:${NODE_VERSION}-bookworm-slim AS node

# Reuse Docker's static client and Compose plugin; the daemon stays on the host.
FROM docker:cli AS docker-cli

# Docker does not support variable expansion directly in COPY --from image
# references. Resolve the uv image in a named stage instead.
FROM ghcr.io/astral-sh/uv:${UV_VERSION} AS uv

FROM ${CODE_SERVER_BASE_IMAGE}

ARG CLAUDE_CODE_VERSION=latest
ARG CODEX_CLI_VERSION=latest
ARG OPENCODE_CLI_VERSION=latest

USER root

# Install GitHub CLI first so it is available before the rest of the toolchain.
RUN apt-get update \
    && apt-get install -y --no-install-recommends gh \
    && gh --version \
    && apt-get install -y --no-install-recommends \
        build-essential \
        fd-find \
        jq \
        libffi-dev \
        libssl-dev \
        less \
        pkg-config \
        python3 \
        python3-dev \
        python3-pip \
        python3-venv \
        ripgrep \
        tree \
        unzip \
        zip \
    && rm -rf /var/lib/apt/lists/*

# Copy uv from Astral's official image.
COPY --from=uv /uv /uvx /usr/local/bin/
COPY --from=docker-cli /usr/local/bin/docker /usr/local/bin/docker
COPY --from=docker-cli /usr/local/libexec/docker/cli-plugins/docker-compose /usr/local/libexec/docker/cli-plugins/docker-compose

# Use Node.js 24 explicitly; the apt package in the base image may be older.
# Copy the complete /usr/local tree so npm's symlinks and support files remain
# consistent with the Node.js binary.
COPY --from=node /usr/local/ /usr/local/

RUN node --version \
    && npm --version \
    && node -e "if (Number(process.versions.node.split('.')[0]) <= 22) process.exit(1)"

# Install the terminal coding agents globally. The version args can be pinned
# in .env when a reproducible toolchain is required.
RUN npm install --global \
        "@anthropic-ai/claude-code@${CLAUDE_CODE_VERSION}" \
        "@openai/codex@${CODEX_CLI_VERSION}" \
        "@opencode/cli@${OPENCODE_CLI_VERSION}" \
    && npm cache clean --force

ENV PATH="/home/coder/.local/bin:${PATH}"
ENV ENTRYPOINTD=/usr/local/lib/code-server/entrypoint.d

COPY scripts/entrypoint.d/10-code-server-setup.sh ${ENTRYPOINTD}/10-code-server-setup.sh
COPY scripts/docker-entrypoint.sh /usr/local/bin/oia-code-server-entrypoint
RUN chmod +x \
        ${ENTRYPOINTD}/10-code-server-setup.sh \
        /usr/local/bin/oia-code-server-entrypoint

USER 1000
WORKDIR /home/coder

ENTRYPOINT ["/usr/local/bin/oia-code-server-entrypoint", "--bind-addr", "0.0.0.0:8080", "."]
