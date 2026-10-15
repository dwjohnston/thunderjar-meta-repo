# Meta-repo dev container image.
#
# Build context is .devcontainer/ (see compose.yaml). Docker-in-Docker is not
# installed here: it comes from the official docker-in-docker feature declared in
# devcontainer.json.

# Pinned to an Ubuntu release. Bump deliberately.
FROM mcr.microsoft.com/devcontainers/base:ubuntu-24.04

# Pinned nvm installer version.
ARG NVM_VERSION=v0.40.3

ARG DEBIAN_FRONTEND=noninteractive

# ---------------------------------------------------------------------------
# Build-time proxy
#
# Set via `proxy.buildtime` in meta-repo.local.yaml; apply.sh passes them as
# build args. ARGs are visible to RUN steps as environment variables but are
# NOT persisted in the final image's environment. Empty means "no proxy".
#
# The runtime proxy is configured separately, as container environment
# variables in compose.local.yaml (from `proxy.runtime`).
# ---------------------------------------------------------------------------
ARG BUILDTIME_HTTP_PROXY=""
ARG BUILDTIME_HTTPS_PROXY=""
ARG BUILDTIME_NO_PROXY=""
ARG HTTP_PROXY=${BUILDTIME_HTTP_PROXY}
ARG http_proxy=${BUILDTIME_HTTP_PROXY}
ARG HTTPS_PROXY=${BUILDTIME_HTTPS_PROXY}
ARG https_proxy=${BUILDTIME_HTTPS_PROXY}
ARG NO_PROXY=${BUILDTIME_NO_PROXY}
ARG no_proxy=${BUILDTIME_NO_PROXY}

# ---------------------------------------------------------------------------
# Custom CA certificates (e.g. a corporate TLS-inspecting proxy)
#
# 1. Put PEM-encoded certs with a .crt extension in .devcontainer/certs/
# 2. Uncomment the blocks below.
# ---------------------------------------------------------------------------
# COPY certs/ /usr/local/share/ca-certificates/meta-repo/
# RUN update-ca-certificates
#
# Make tools that don't use the system store trust the certs too:
# ENV NODE_EXTRA_CA_CERTS=/etc/ssl/certs/ca-certificates.crt \
#     REQUESTS_CA_BUNDLE=/etc/ssl/certs/ca-certificates.crt \
#     SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt \
#     CURL_CA_BUNDLE=/etc/ssl/certs/ca-certificates.crt

# ---------------------------------------------------------------------------
# System packages + GitHub CLI
# ---------------------------------------------------------------------------
RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates curl git gnupg unzip \
    && mkdir -p -m 755 /etc/apt/keyrings \
    && curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
        -o /etc/apt/keyrings/githubcli-archive-keyring.gpg \
    && chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
        > /etc/apt/sources.list.d/github-cli.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends gh \
    && rm -rf /var/lib/apt/lists/*

# /workspace is the container's workspace root. Create it owned by vscode so
# Docker doesn't create it as root when mounting folders into it.
RUN mkdir -p /workspace && chown vscode:vscode /workspace

# ---------------------------------------------------------------------------
# User-level tools (installed as vscode)
# ---------------------------------------------------------------------------
USER vscode
WORKDIR /home/vscode

# Pre-create the persisted agent-state directories (and their parents) owned by
# vscode. Otherwise Docker creates the parents as root when it mounts the named
# volumes, which breaks e.g. the VS Code server install in ~/.vscode-server.
RUN mkdir -p \
        /home/vscode/.copilot \
        /home/vscode/.claude \
        /home/vscode/.vscode-server/data/agentSessionData \
        /home/vscode/.vscode-server/data/User/globalStorage

# nvm + latest LTS Node. Repos with an .nvmrc can `nvm use` their own version.
ENV NVM_DIR=/home/vscode/.nvm
RUN curl -fsSL "https://raw.githubusercontent.com/nvm-sh/nvm/${NVM_VERSION}/install.sh" | PROFILE=/dev/null bash \
    && . "$NVM_DIR/nvm.sh" \
    && nvm install --lts \
    && nvm alias default 'lts/*' \
    # Stable path to the default Node, so it is on PATH in non-interactive shells too.
    && ln -sfn "$NVM_DIR/versions/node/$(nvm version default)" "$NVM_DIR/default-node" \
    && for rc in ~/.bashrc ~/.zshrc; do \
        printf '\nexport NVM_DIR="%s"\n[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"\n[ -s "$NVM_DIR/bash_completion" ] && [ -n "$BASH_VERSION" ] && . "$NVM_DIR/bash_completion"\n' "$NVM_DIR" >> "$rc"; \
    done

# bun (latest at build time)
RUN curl -fsSL https://bun.sh/install | bash

# Claude Code CLI (latest at build time; it updates itself afterwards)
RUN curl -fsSL https://claude.ai/install.sh | bash

ENV PATH=/home/vscode/.local/bin:/home/vscode/.bun/bin:/home/vscode/.nvm/default-node/bin:${PATH}

# ---------------------------------------------------------------------------
# Runtime environment
#
# Runtime proxy variables (HTTP_PROXY / HTTPS_PROXY / NO_PROXY and lowercase
# variants) are injected by compose.local.yaml from `proxy.runtime`, so they
# can differ from the build-time proxy. Add any other static environment
# variables the whole team needs here, e.g.:
# ENV SOME_TOOL_HOME=/opt/some-tool
# ---------------------------------------------------------------------------

# The container starts as root so the entrypoint can fix volume ownership.
# Dev Containers connects as `vscode` (remoteUser in devcontainer.json).
USER root

# Also load nvm in login shells (e.g. `bash -lc`); ~/.bashrc only covers
# interactive shells.
RUN printf 'export NVM_DIR="%s"\n[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"\n' "$NVM_DIR" > /etc/profile.d/nvm.sh

COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod 755 /usr/local/bin/docker-entrypoint.sh

ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
CMD ["sleep", "infinity"]
