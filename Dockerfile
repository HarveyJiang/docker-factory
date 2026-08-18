# syntax=docker/dockerfile:1
FROM oven/bun:1.3.14 AS base
WORKDIR /app

FROM base AS deps
WORKDIR /app
COPY package.json bun.lock ./
COPY bun-patches ./bun-patches
COPY packages/ui/package.json ./packages/ui/
COPY packages/web/package.json ./packages/web/
COPY packages/electron/package.json ./packages/electron/
COPY packages/vscode/package.json ./packages/vscode/
COPY packages/mobile/package.json ./packages/mobile/
RUN bun install --frozen-lockfile --ignore-scripts

# Runtime production deps only. The full install pulls in devDependencies for
# electron/vscode/mobile packages (electron-builder, vite, typescript, oxlint,
# vsce-sign, ...) that are several hundred MB and never used at runtime.
# Start fresh from base (no node_modules) so bun only installs production deps.
FROM base AS prod-deps
WORKDIR /app
COPY package.json bun.lock ./
COPY bun-patches ./bun-patches
COPY packages/ui/package.json ./packages/ui/
COPY packages/web/package.json ./packages/web/
COPY packages/electron/package.json ./packages/electron/
COPY packages/vscode/package.json ./packages/vscode/
COPY packages/mobile/package.json ./packages/mobile/
RUN bun install --frozen-lockfile --ignore-scripts --production

FROM deps AS builder
WORKDIR /app
COPY . .
RUN bun run build:web

FROM oven/bun:1.3.14 AS runtime
WORKDIR /home/openchamber

RUN apt-get update && apt-get install -y --no-install-recommends \
  bash \
  ca-certificates \
  curl \
  git \
  jq \
  less \
  openssh-client \
  python3 \
  python3-pip \
  python3-requests \
  tzdata \
  unzip \
  wget \
  zip \
  && rm -rf /var/lib/apt/lists/*

# GitHub CLI (gh) via official apt repo - needed for GitHub Pages publishing,
# repo management (gh repo create/api/release) and git push/pull over HTTPS.
RUN curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
    | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg \
  && chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg \
  && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" > /etc/apt/sources.list.d/github-cli.list \
  && apt-get update \
  && apt-get install -y --no-install-recommends gh \
  && rm -rf /var/lib/apt/lists/*

# Latest Node LTS - apt's nodejs is stale (v20) and wrangler (Cloudflare Workers/Pages)
# requires Node >=22. Bump node_ver here to upgrade later.
RUN node_ver="v24.19.0" \
  && node_arch="$(case "$(dpkg --print-architecture)" in amd64) echo x64;; arm64) echo arm64;; esac)" \
  && curl -fsSL -o /tmp/node.tar.gz "https://nodejs.org/dist/${node_ver}/node-${node_ver}-linux-${node_arch}.tar.gz" \
  && tar -xzf /tmp/node.tar.gz -C /usr/local --strip-components=1 \
  && rm -f /tmp/node.tar.gz \
  && node --version && npm --version

# Use Beijing time (UTC+8) for the container's clock and TZ env
ENV TZ=Asia/Shanghai
RUN ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime \
  && echo "Asia/Shanghai" > /etc/timezone

# Replace the base image's 'bun' user (UID 1000) with 'openchamber'
# so mounted volumes with 1000:1000 ownership work correctly.
RUN userdel bun \
  && groupadd -g 1000 openchamber \
  && useradd -u 1000 -g 1000 -m -s /bin/bash openchamber \
  && chown -R openchamber:openchamber /home/openchamber

# Switch to openchamber user
USER openchamber

ENV NPM_CONFIG_PREFIX=/home/openchamber/.npm-global
ENV PATH=${NPM_CONFIG_PREFIX}/bin:${PATH}
# wrangler caches under node_modules/.cache (root-owned) by default, which the
# non-root user cannot write - redirect to the persistent .config volume.
ENV WRANGLER_CACHE_DIR=/home/openchamber/.config/.wrangler/cache

RUN npm config set prefix /home/openchamber/.npm-global && mkdir -p /home/openchamber/.npm-global && \
  mkdir -p /home/openchamber/.local /home/openchamber/.config /home/openchamber/.ssh && \
  npm install -g --cache /tmp/npm-cache opencode-ai wrangler && \
  rm -rf /tmp/npm-cache /home/openchamber/.npm

# cloudflared 2026.3.0 - update digest explicitly when upgrading
COPY --from=cloudflare/cloudflared@sha256:6d91c121b803126f7a5344005d17a9324788fc09d305b6e2560ec6040a7ae283 /usr/local/bin/cloudflared /usr/local/bin/cloudflared

ENV NODE_ENV=production

COPY scripts/docker-entrypoint.sh /home/openchamber/openchamber-entrypoint.sh

COPY --from=prod-deps /app/node_modules ./node_modules
COPY --from=prod-deps /app/packages/web/node_modules ./packages/web/node_modules
COPY --from=builder /app/package.json ./package.json
COPY --from=builder /app/packages/web/package.json ./packages/web/package.json
COPY --from=builder /app/packages/web/bin ./packages/web/bin
COPY --from=builder /app/packages/web/server ./packages/web/server
COPY --from=builder /app/packages/web/dist ./packages/web/dist

EXPOSE 3000

ENTRYPOINT ["sh", "/home/openchamber/openchamber-entrypoint.sh"]
