#!/usr/bin/env bash
# check-config.sh
# 容器升级/重建后的配置体检脚本。
# 所有关键配置都存放在持久卷 (.config/.local/.ssh/workspaces)，
# 升级容器不丢。本脚本逐项核对，缺什么报什么。
#
# 用法: bash check-config.sh   (无需 root)

set -u

PASS=0
FAIL=0

ok()   { echo "  [OK]   $1"; PASS=$((PASS+1)); }
miss() { echo "  [MISS] $1  <-- 需要处理"; FAIL=$((FAIL+1)); }

check_file() { # $1 描述, $2 路径
  if [ -e "$2" ]; then ok "$1 ($2)"; else miss "$1 ($2)"; fi
}

echo "== 持久卷检查 =="
grep -q "/home/openchamber/.config " /proc/self/mounts && ok ".config 卷已挂载" || miss ".config 卷未挂载"
grep -q "/home/openchamber/.local "  /proc/self/mounts && ok ".local 卷已挂载"  || miss ".local 卷未挂载"
grep -q "/home/openchamber/.ssh "    /proc/self/mounts && ok ".ssh 卷已挂载"    || miss ".ssh 卷未挂载"
grep -q "/home/openchamber/workspaces " /proc/self/mounts && ok "workspaces 卷已挂载" || miss "workspaces 卷未挂载"

echo
echo "== OpenCode / Cloudflare MCP 配置 =="
check_file "opencode 全局配置(5个MCP服务器)" "$HOME/.config/opencode/opencode.jsonc"
check_file "MCP OAuth token(cloudflare等4个)" "$HOME/.local/share/opencode/mcp-auth.json"
check_file "Cloudflare Skills" "$HOME/.config/opencode/skills/cloudflare/SKILL.md"
if [ -f "$HOME/.config/opencode/opencode.jsonc" ]; then
  n=$(grep -c '"type": "remote"' "$HOME/.config/opencode/opencode.jsonc" 2>/dev/null)
  [ "$n" -ge 5 ] && ok "opencode.jsonc 含 $n 个 remote MCP 服务器" || miss "opencode.jsonc 里 MCP 服务器不足5个(当前$n)"
fi

echo
echo "== wrangler / Cloudflare CLI 凭证 =="
check_file "wrangler OAuth 凭证" "$HOME/.config/.wrangler/config/default.toml"
check_file "Cloudflare API token(DNS)" "$HOME/.config/.cloudflare/api-token"
if [ -f "$HOME/.config/.cloudflare/api-token" ]; then
  t=$(cat "$HOME/.config/.cloudflare/api-token" 2>/dev/null)
  case "$t" in
    "YOUR_CLOUDFLARE_API_TOKEN_HERE"|"") miss "api-token 还是占位符，未替换";;
    *) ok "api-token 已替换 (${#t} 字符)";;
  esac
fi
check_file "cfdns.sh (DNS 管理脚本)" "$HOME/workspaces/openchamber-docker/cfdns.sh"

echo
echo "== 1Panel 面板 API =="
check_file "1Panel API token" "$HOME/.config/.1panel/api-token"
if [ -f "$HOME/.config/.1panel/api-token" ]; then
  t=$(cat "$HOME/.config/.1panel/api-token" 2>/dev/null)
  case "$t" in
    "YOUR_1PANEL_API_TOKEN_HERE"|"") miss "1Panel api-token 还是占位符，未替换";;
    *) ok "1Panel api-token 已替换 (${#t} 字符)";;
  esac
fi

echo
echo "== GitHub (gh CLI) 配置 =="
check_file "gh 登录凭证" "$HOME/.config/gh/hosts.yml"
check_file "gh 二进制 (持久)" "$HOME/.local/bin/gh"
check_file "git 全局配置" "$HOME/.config/git/config"
check_file "git 凭证(store兜底)" "$HOME/.config/git-credentials"

echo
echo "== OpenChamber 平台配置 =="
check_file "settings.json" "$HOME/.config/openchamber/settings.json"

echo
echo "== 结果 =="
echo "  通过: $PASS   缺失: $FAIL"
if [ "$FAIL" -gt 0 ]; then
  echo "  有配置丢失！按上面 [MISS] 行处理。"
  exit 1
else
  echo "  全部就位，无需处理。"
  exit 0
fi