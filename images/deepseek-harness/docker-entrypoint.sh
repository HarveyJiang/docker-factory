#!/bin/sh
set -eu
# Harness 禁止 --host 0.0.0.0，需用 socat 将 0.0.0.0:3000 代理到 127.0.0.1:3000
# 用法：docker run ghcr.io/.../deepseek-harness web --port 3000 --trusted-host ...
PORT="${DSH_PORT:-3000}"
if [ "$1" = "web" ]; then
  echo "[entrypoint] starting socat proxy 0.0.0.0:${PORT} -> 127.0.0.1:${PORT}"
  socat TCP-LISTEN:${PORT},fork,reuseaddr TCP:127.0.0.1:${PORT} &
  SOCAT_PID=$!
  trap "kill $SOCAT_PID || true" EXIT
  # 确保 socat 已监听再启动 dsh
  sleep 1
fi
exec pnpm dsh "$@"
