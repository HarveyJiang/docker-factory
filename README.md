# Docker Factory 🏭

> 统一镜像工厂：一仓库多镜像，Base+App 双层 + 双缓存，每周自动巡检上游

[![build-openchamber-base](https://github.com/HarveyJiang/docker-factory/actions/workflows/build-openchamber-base.yml/badge.svg)](https://github.com/HarveyJiang/docker-factory/actions/workflows/build-openchamber-base.yml)
[![build-openchamber](https://github.com/HarveyJiang/docker-factory/actions/workflows/build-openchamber.yml/badge.svg)](https://github.com/HarveyJiang/docker-factory/actions/workflows/build-openchamber.yml)
[![build-deepseek-harness-base](https://github.com/HarveyJiang/docker-factory/actions/workflows/build-deepseek-harness-base.yml/badge.svg)](https://github.com/HarveyJiang/docker-factory/actions/workflows/build-deepseek-harness-base.yml)
[![build-deepseek-harness](https://github.com/HarveyJiang/docker-factory/actions/workflows/build-deepseek-harness.yml/badge.svg)](https://github.com/HarveyJiang/docker-factory/actions/workflows/build-deepseek-harness.yml)

原 `openchamber-docker` 已重命名为 `docker-factory`，旧地址自动 301 跳转。

---

## 📦 镜像总览

| 镜像 | GHCR | 上游 | 基础层 | 应用层 | 巡检 |
|------|------|------|--------|--------|------|
| **openchamber-base** | `ghcr.io/harveyjiang/openchamber-base:latest` | - | `images/openchamber/Dockerfile.base`<br>`oven/bun:1.3.14` + `openjdk-21/maven` + `python3/node24/gh/cloudflared` | - | 每周一 02:00 UTC + `paths` |
| **openchamber** | `ghcr.io/harveyjiang/openchamber:latest` | [btriapitsyn/openchamber](https://github.com/btriapitsyn/openchamber) `main` | `FROM openchamber-base` | `bun install` + `build:web` (vite) | 每周一 03:00 UTC + `LAST_BUILD` |
| **deepseek-harness-base** | `ghcr.io/harveyjiang/deepseek-harness-base:latest` | - | `images/deepseek-harness/Dockerfile.base`<br>`node:24-bookworm` + `pnpm@11.7.0` + `python3` | - | 每周一 02:00 UTC + `paths` |
| **deepseek-harness** | `ghcr.io/harveyjiang/deepseek-harness:latest` | [deepseek-ai/deepseek-harness](https://github.com/deepseek-ai/deepseek-harness) `master` | `FROM deepseek-harness-base` | `pnpm install` + `pnpm run build` | 每周一 03:00 UTC + `LAST_BUILD_DSH` |

**缓存策略：** `Base` 用 `registry:cache`，`App` 用 `registry+gha` 双缓存。仅改基础包时 `App` 30s 内完成（`build:web` 命中）；`web` 未变更时增量 vite；上游无更新则 `skip`。

---

## 🚀 快速使用

```bash
# openchamber (原 openchamber-docker)
docker pull ghcr.io/harveyjiang/openchamber:latest
docker run -p 3000:3000 ghcr.io/harveyjiang/openchamber

# deepseek-harness
docker pull ghcr.io/harveyjiang/deepseek-harness:latest
docker run -it --rm ghcr.io/harveyjiang/deepseek-harness dsh --help
docker run -it --rm -p 3000:3000 ghcr.io/harveyjiang/deepseek-harness web
```

---

## 📁 目录结构

```
docker-factory/
├── images/
│   ├── openchamber/
│   │   ├── Dockerfile.base   # 重依赖，月级变更
│   │   └── Dockerfile        # FROM base + builder cache (syntax 1.6)
│   └── deepseek-harness/
│       ├── Dockerfile.base   # Node24+pnpm+Python
│       └── Dockerfile        # FROM base + pnpm build
├── .github/workflows/
│   ├── build-openchamber-base.yml
│   ├── build-openchamber.yml
│   ├── build-deepseek-harness-base.yml
│   └── build-deepseek-harness.yml
└── LAST_BUILDS.json          # {"openchamber":"<sha>","deepseek-harness":"<sha>"}
```

---

## ➕ 新增镜像（以 `langflow` 为例，3 步）

1. **创建目录**
```bash
mkdir -p images/langflow
# 编写 images/langflow/Dockerfile.base (系统层) 和 Dockerfile (FROM base)
```

2. **复制工作流**
```bash
cp .github/workflows/build-deepseek-harness-base.yml .github/workflows/build-langflow-base.yml
cp .github/workflows/build-deepseek-harness.yml .github/workflows/build-langflow.yml
# 修改 3 处：IMAGE, UPSTREAM_REPO/BRANCH, paths
```

3. **推送即自动构建**
```bash
git add images/langflow .github/workflows/build-langflow*.yml
git commit -m "feat: add langflow image"
git push
# 手动触发: gh workflow run build-langflow --repo HarveyJiang/docker-factory -f force=true
```

---

## ⏰ 巡检规则

- **Base 层**：`push` 触发 `paths: [images/<name>/Dockerfile.base]` + `schedule: '0 2 * * 1'` + `workflow_dispatch`
- **App 层**：`schedule: '0 3 * * 1'` 先 `git ls-remote` 上游，对比 `LAST_BUILD*`，无变更 `skip`，有变更则 `clone → cp Dockerfile → build-push`

---

## 🔧 本地调试

```bash
# 构建 base
docker build -f images/openchamber/Dockerfile.base -t ghcr.io/harveyjiang/openchamber-base:local .

# 构建 app（需先有 base）
docker build -f images/openchamber/Dockerfile -t ghcr.io/harveyjiang/openchamber:local --build-arg BASE_TAG=local .
```

---

## 📌 迁移说明

- 2025-08-27: `openchamber-docker` → `docker-factory`，扁平 `Dockerfile` → `images/<name>/`
- 旧镜像 `ghcr.io/harveyjiang/openchamber-docker` / `openchamber-docker-base` 仍保留，新镜像为 `.../openchamber` / `.../openchamber-base`
