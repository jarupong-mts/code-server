# syntax=docker/dockerfile:1

ARG CODE_SERVER_BASE_IMAGE=ghcr.io/coder/code-server:latest
ARG UV_VERSION=latest

# Docker does not support variable expansion directly in COPY --from image
# references. Resolve the uv image in a named stage instead.
FROM ghcr.io/astral-sh/uv:${UV_VERSION} AS uv

FROM ${CODE_SERVER_BASE_IMAGE}

ARG CLAUDE_CODE_VERSION=latest
ARG CODEX_CLI_VERSION=latest
ARG OPENCODE_CLI_VERSION=latest

USER root

# The code-server image already provides git, git-lfs, curl, sudo, ssh, and
# useful shell tools. Add the language/runtime tools needed by this workspace.
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        build-essential \
        fd-find \
        jq \
        libffi-dev \
        libssl-dev \
        less \
        nodejs \
        npm \
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
