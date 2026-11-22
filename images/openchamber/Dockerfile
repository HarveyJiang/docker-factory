# syntax=docker/dockerfile:1.6
# openchamber 单镜像多阶段构建
# - deps/prod-deps/builder：用 oven/bun 装依赖并构建（builder 在 BUILDPLATFORM 上跑，避免 QEMU 重复编译）
# - runtime：内联系统依赖（Java/Maven/Python/Node/gh/cloudflared）+ 只拷贝构建产物
# bun 1.4.5 对齐上游 packageManager bun@1.4.5

# ---------- 依赖安装 ----------
FROM oven/bun:1.4.5 AS base
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
COPY packages/sdk/package.json ./packages/sdk/
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
COPY packages/sdk/package.json ./packages/sdk/
RUN bun install --frozen-lockfile --ignore-scripts --production \
  && rm -rf \
    node_modules/onnxruntime-node \
    node_modules/onnxruntime-web \
    node_modules/onnxruntime-common \
    node_modules/onnx-proto \
    node_modules/@xenova \
    node_modules/sherpa-onnx-node \
    node_modules/sherpa-onnx-linux-arm64 \
    node_modules/.bun/install/cache/onnxruntime-node@* \
    node_modules/.bun/install/cache/onnxruntime-web@* \
    node_modules/.bun/install/cache/onnxruntime-common@* \
    node_modules/.bun/install/cache/onnx-proto@* \
    node_modules/.bun/install/cache/@xenova+* \
    node_modules/.bun/install/cache/sherpa-onnx-node@* \
    node_modules/.bun/install/cache/sherpa-onnx-linux-arm64@*

# Builder: 只在本机架构(BUILDPLATFORM, GitHub runner 为 amd64)上构建一次。
# vite/server 构建输出跨平台一致，无需在 arm64/qemu 上重复编译，省一半+构建时间。
# (deps/prod-deps 的 node_modules 仍是目标平台各自安装)
FROM --platform=$BUILDPLATFORM deps AS builder
WORKDIR /app
# 利用 BuildKit cache + 层缓存：web 未变更时直接命中缓存，变更时增量编译
COPY . .
# server 运行时 import @openchamber/sdk, 而 deps 安装用了 --ignore-scripts
# 导致 root postinstall 未构建它, 需在此先构建出 dist 供 runtime 阶段拷贝
RUN bun run --cwd packages/sdk build
# build:web = build:server(打包 server+cli 进 packages/web/build) + vite(前端进 dist)
RUN --mount=type=cache,target=/root/.cache \
    --mount=type=cache,target=/app/node_modules/.cache \
    --mount=type=cache,target=/app/packages/web/node_modules/.vite \
    bun run build:web

# ---------- 运行时 ----------
FROM oven/bun:1.4.5 AS runtime
WORKDIR /home/openchamber

# 1. 系统包 + Java/Maven/Python（供容器内交互式开发）
# trixie 已无 openjdk-17，使用 21 (兼容 17，且为当前 LTS)
# openjdk-21-jdk-headless: 服务器无图形环境，砍 AWT/Swing 图形库，体积更小
RUN apt-get update && apt-get install -y --no-install-recommends \
  bash \
  bzip2 \
  build-essential \
  ca-certificates \
  curl \
  git \
  git-lfs \
  jq \
  less \
  openssh-client \
  pkg-config \
  python3 \
  python3-dev \
  python3-pip \
  python3-requests \
  python3-venv \
  libssl-dev \
  tzdata \
  unzip \
  wget \
  xz-utils \
  zip \
  zstd \
  openjdk-21-jdk-headless \
  maven \
  && java -version && mvn -version \
  && rm -rf /var/lib/apt/lists/*

# 2. GitHub CLI
RUN curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
    | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg \
  && chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg \
  && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" > /etc/apt/sources.list.d/github-cli.list \
  && apt-get update && apt-get install -y --no-install-recommends gh \
  && rm -rf /var/lib/apt/lists/*

# 3. Node.js LTS (wrangler 需要 >=22，上游 engines 要求 >=24.14)
RUN node_ver="v24.19.0" \
  && node_arch="$(case "$(dpkg --print-architecture)" in amd64) echo x64;; arm64) echo arm64;; esac)" \
  && curl -fsSL -o /tmp/node.tar.gz "https://nodejs.org/dist/${node_ver}/node-${node_ver}-linux-${node_arch}.tar.gz" \
  && tar -xzf /tmp/node.tar.gz -C /usr/local --strip-components=1 \
  && rm -f /tmp/node.tar.gz \
  && node --version && npm --version

# 4. 时区 + 用户（替换基础镜像的 bun 用户，保留 UID 1000 以便挂载卷权限正确）
ENV TZ=Asia/Shanghai
RUN ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime \
  && echo "Asia/Shanghai" > /etc/timezone

RUN userdel bun \
  && groupadd -g 1000 openchamber \
  && useradd -u 1000 -g 1000 -m -s /bin/bash openchamber \
  && chown -R openchamber:openchamber /home/openchamber

USER openchamber

ENV NPM_CONFIG_PREFIX=/home/openchamber/.npm-global
ENV PATH=${NPM_CONFIG_PREFIX}/bin:${PATH}
ENV WRANGLER_CACHE_DIR=/home/openchamber/.config/.wrangler/cache

# opencode 跟随上游最新版：版本号由 CI 经 OPENCODE_VERSION 传进来，
# 本地构建不传参时默认 latest。版本变化会自动使该层缓存失效重装，
# 上游没发版则命中缓存，不浪费构建时间。
# 仅保留当前平台（arm64）的二进制，删掉多余的 musl 平台包，省 ~200MB。
ARG OPENCODE_VERSION=latest
RUN npm config set prefix /home/openchamber/.npm-global && mkdir -p /home/openchamber/.npm-global && \
  mkdir -p /home/openchamber/.local /home/openchamber/.config /home/openchamber/.ssh && \
  npm install -g --cache /tmp/npm-cache @opencode/cli@${OPENCODE_VERSION} wrangler pnpm yarn typescript && \
  # 只保留与基础镜像 glibc 匹配的 arm64 二进制，删除 musl 等多余平台包
  find /home/openchamber/.npm-global/lib/node_modules/@opencode/cli/node_modules/@opencode \
    -mindepth 1 -maxdepth 1 -type d ! -name "cli-linux-arm64" -exec rm -rf {} + && \
  npm ls -g @opencode/cli && \
  rm -rf /tmp/npm-cache /home/openchamber/.npm

# 5. cloudflared
COPY --from=cloudflare/cloudflared@sha256:6d91c121b803126f7a5344005d17a9324788fc09d305b6e2560ec6040a7ae283 /usr/local/bin/cloudflared /usr/local/bin/cloudflared

ENV NODE_ENV=production
# 基础镜像默认 POSIX locale，内建终端里 bash readline 会把多字节字符按字节拆开，
# 导致中文等输入/显示异常。统一 UTF-8。
ENV LANG=C.UTF-8

COPY scripts/docker-entrypoint.sh /home/openchamber/openchamber-entrypoint.sh

# 运行产物：production node_modules + 构建输出
COPY --from=prod-deps /app/node_modules ./node_modules
COPY --from=prod-deps /app/packages/web/node_modules ./packages/web/node_modules
COPY --from=builder /app/package.json ./package.json
COPY --from=builder /app/packages/web/package.json ./packages/web/package.json
# 2.8.0 起 server 与 cli 打包进 build/（main: ./build/server/index.js, bin: ./build/bin/cli.js），
# 运行时入口为 packages/web/build/bin/cli.js，不再需要源码目录 bin/ server/
COPY --from=builder /app/packages/web/build ./packages/web/build
COPY --from=builder /app/packages/web/dist ./packages/web/dist
# server 运行时依赖 @openchamber/sdk (main 指向 dist/index.js), 必须拷 dist
COPY --from=builder /app/packages/sdk/package.json ./packages/sdk/package.json
COPY --from=builder /app/packages/sdk/dist ./packages/sdk/dist

EXPOSE 3000

ENTRYPOINT ["sh", "/home/openchamber/openchamber-entrypoint.sh"]
