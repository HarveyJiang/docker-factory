# syntax=docker/dockerfile:1.6
# mind-python 单阶段镜像：Python 3.13 + FastAPI + 金融数据/爬虫依赖
FROM python:3.13-slim

WORKDIR /app

# 系统依赖：build-essential（编译 C 扩展）、nodejs/npm（PyExecJS 调用）
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    ca-certificates \
    curl \
    git \
    nodejs \
    npm \
    tzdata \
    bash \
    && rm -rf /var/lib/apt/lists/*

ENV TZ=Asia/Shanghai
RUN ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime \
    && echo "Asia/Shanghai" > /etc/timezone

ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PIP_NO_CACHE_DIR=1

# uv 加速依赖安装
COPY --from=ghcr.io/astral-sh/uv:latest /uv /uvx /bin/

# 先装依赖（requirements.txt 变更才重装，命中缓存秒级）
COPY pyproject.toml requirements.txt ./
RUN --mount=type=cache,target=/root/.cache/pip \
    uv pip install --system --no-cache-dir -r requirements.txt \
    && pip install --no-cache-dir websockets==12.0 loguru

# 上游源码
COPY . .

RUN mkdir -p /app/logs

EXPOSE 3040 3050 8080

HEALTHCHECK --interval=30s --timeout=10s --retries=3 \
  CMD python3 -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8080/healthz', timeout=5)"

# 多端口多 worker 高并发启动（与上游 docker-compose 对齐：3040/3050/8080 各 2 worker）
CMD ["sh", "-c", "uvicorn app.main:app --host 0.0.0.0 --port 3040 --workers 2 & \
                  uvicorn app.main:app --host 0.0.0.0 --port 3050 --workers 2 & \
                  uvicorn app.main:app --host 0.0.0.0 --port 8080 --workers 2 & \
                  wait"]
