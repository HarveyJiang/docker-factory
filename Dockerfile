# syntax=docker/dockerfile:1.6
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
# 利用 BuildKit cache + 层缓存：web 未变更时直接命中缓存，变更时增量编译
COPY . .
RUN --mount=type=cache,target=/root/.cache \
    --mount=type=cache,target=/app/node_modules/.cache \
    --mount=type=cache,target=/app/packages/web/node_modules/.vite \
    bun run build:web

# Runtime: 使用预构建的基础镜像（包含 Java/Maven/Python/Node/gh 等重依赖）
# 基础镜像由 Dockerfile.base 构建，推送到 ghcr.io/harveyjiang/openchamber-docker-base
# 优势：应用层构建只需 30s 左右，无需每次重装 apt 包
FROM ghcr.io/harveyjiang/openchamber-docker-base:latest AS runtime
WORKDIR /home/openchamber
# 基础镜像已包含所有系统依赖，此处仅继承环境变量和用户
# 如需本地无网络构建，可回退为: FROM oven/bun:1.3.14 AS runtime + 手动安装

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
