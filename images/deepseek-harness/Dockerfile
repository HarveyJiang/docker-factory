# syntax=docker/dockerfile:1.6
# DeepSeek Harness 应用层：FROM base，增量编译
# 基础镜像由 images/deepseek-harness/Dockerfile.base 构建
FROM ghcr.io/harveyjiang/deepseek-harness-base:latest AS builder
WORKDIR /app

# 依赖清单（分层缓存）
COPY pnpm-lock.yaml pnpm-workspace.yaml package.json ./
COPY patches ./patches
COPY vendor ./vendor
COPY packages ./packages
COPY apps ./apps
COPY native ./native
COPY python ./python
COPY scripts ./scripts
COPY tsconfig.*.json vitest*.config.ts tsdown.config.ts knip.json lefthook.yml .oxlintrc.json ./
COPY . .

# 安装 + 构建（BuildKit cache 复用，web 未变更时 15-30s）
RUN --mount=type=cache,target=/root/.local/share/pnpm/store \
    pnpm install --frozen-lockfile \
 && pnpm run build

# ---------- runtime ----------
FROM ghcr.io/harveyjiang/deepseek-harness-base:latest AS runtime
WORKDIR /app
COPY --from=builder /app ./

ENV TZ=Asia/Shanghai
ENV NODE_ENV=production
EXPOSE 3000

ENTRYPOINT ["pnpm", "dsh"]
CMD ["web", "--help"]
