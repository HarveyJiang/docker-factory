#!/usr/bin/env bash
# 1Panel API 封装 —— 自动算签名，直接调
# 用法: ./1panel-api.sh <METHOD> <PATH> [JSON_BODY]
# 例:
#   ./1panel-api.sh GET /api/v2/toolbox/device/base
#   ./1panel-api.sh POST /api/v2/toolbox/device/base '{}'
#   ./1panel-api.sh GET /api/v2/websites

set -u

KEY_FILE="${HOME}/.config/.1panel/api-token"
BASE_URL="${PANEL_URL:-https://app.2020224.xyz}"
METHOD="${1:-GET}"
PATH_="${2:-/}"
BODY="${3:-}"

if [ ! -f "$KEY_FILE" ]; then echo "error: $KEY_FILE not found" >&2; exit 1; fi
API_KEY=$(cat "$KEY_FILE")
TS=$(date +%s)
TOK=$(printf '%s' "1panel${API_KEY}${TS}" | md5sum | awk '{print $1}')

ARGS=(-s -m 30 -w $'\n[%{http_code}]\n')
ARGS+=(-H "1Panel-Token: ${TOK}")
ARGS+=(-H "1Panel-Timestamp: ${TS}")
ARGS+=(-X "$METHOD")

[ "$METHOD" = "POST" ] && [ -n "$BODY" ] && ARGS+=(-H "Content-Type: application/json" -d "$BODY")

curl "${ARGS[@]}" "${BASE_URL}${PATH_}"
