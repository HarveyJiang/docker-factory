# syntax=docker/dockerfile:1.6
# DeepSeek Harness 应用层：FROM base，分层缓存
# 基础镜像由 images/deepseek-harness/Dockerfile.base 构建

# ---------- deps: 仅锁文件变更时重装，命中时 10s ----------
FROM ghcr.io/harveyjiang/deepseek-harness-base:latest AS deps
WORKDIR /app
COPY pnpm-lock.yaml pnpm-workspace.yaml package.json ./
COPY patches ./patches
COPY vendor ./vendor
# 复制所有 workspace 的 package.json 以解析依赖（利用层缓存）
COPY packages ./packages
COPY apps ./apps
COPY native ./native
COPY python ./python
COPY scripts ./scripts
COPY tsconfig.*.json vitest*.config.ts tsdown.config.ts knip.json lefthook.yml .oxlintrc.json ./
RUN --mount=type=cache,target=/root/.local/share/pnpm/store \
    --mount=type=cache,target=/root/.cache \
    pnpm install --frozen-lockfile

# ---------- builder: 源码变更时增量编译，vite cache 命中 15-30s ----------
FROM deps AS builder
COPY . .
RUN --mount=type=cache,target=/root/.local/share/pnpm/store \
    --mount=type=cache,target=/root/.cache \
    --mount=type=cache,target=/app/node_modules/.cache \
    --mount=type=cache,target=/app/packages/web/node_modules/.vite \
    --mount=type=cache,target=/app/apps/web/.vite \
    pnpm run build

# ---------- runtime ----------
FROM ghcr.io/harveyjiang/deepseek-harness-base:latest AS runtime
WORKDIR /app
COPY --from=builder /app ./
COPY docker-entrypoint.sh /usr/local/bin/dsh-entrypoint.sh
RUN chmod +x /usr/local/bin/dsh-entrypoint.sh

ENV TZ=Asia/Shanghai
ENV NODE_ENV=production
EXPOSE 3000

ENTRYPOINT ["/usr/local/bin/dsh-entrypoint.sh"]
CMD ["web", "--host", "127.0.0.1", "--port", "3000", "--no-open"]
