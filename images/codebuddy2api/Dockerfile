# syntax=docker/dockerfile:1.6
# codebuddy2api 应用层：FROM base，分层缓存
# 基础镜像由 images/codebuddy2api/Dockerfile.base 构建

# ---------- runtime ----------
FROM ghcr.io/harveyjiang/codebuddy2api-base:latest AS runtime
WORKDIR /app

# 源码直接来自上游 clone（workflow 已 cp 本 Dockerfile 到 src/）
COPY core ./core
COPY admin ./admin

# 数据目录（挂载点）
RUN mkdir -p /data/auth /data/management

ENV TZ=Asia/Shanghai \
    PYTHONUNBUFFERED=1 \
    CODEBUDDY_AUTH_DIR=/data/auth \
    MANAGEMENT_DATA_DIR=/data/management

EXPOSE 8787

HEALTHCHECK --interval=30s --timeout=10s --retries=3 \
  CMD python3 -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8787/health', timeout=5)"

# 管理后台模式启动（含协议转换核心 + 中文管理后台）
CMD ["python3", "-m", "admin.server"]
