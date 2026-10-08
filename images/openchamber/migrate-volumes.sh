#!/usr/bin/env bash
# migrate-volumes.sh - 旧版零散卷结构(v1) -> 整目录卷结构(v2) 迁移
#
# 背景: 旧 compose 把 .config/.local 拆成多个子目录卷挂载
# (./data/openchamber、./data/opencode/{share,state,config})，
# 导致 .cloudflare、.wrangler 等凭证目录不在卷里，重装丢失。
# v2 改为整目录挂载 ./data/config -> ~/.config、./data/local -> ~/.local。
#
# 用法: 在宿主机 compose 目录执行:  bash /path/to/migrate-volumes.sh
#   - 幂等：已迁移过的会跳过（标记文件 data/.migrated-v2）
#   - 不删除：旧目录迁移后改名 *.bak-<日期>，确认无误再手动删除
#   - 先备份：脚本会先打一个 data 卷整体 tar 包
#
set -euo pipefail

BASE="$(cd "$(dirname "$0")" && pwd)"   # compose 文件所在目录
DATA="$BASE/data"
STAMP="$(date +%F-%H%M)"
MARK="$DATA/.migrated-v2"

# 旧 -> 新 映射（只处理存在的旧目录）
declare -A MAP=(
  ["$DATA/openchamber"]="$DATA/config/openchamber"
  ["$DATA/opencode/config"]="$DATA/config/opencode"
  ["$DATA/opencode/share"]="$DATA/local/share/opencode"
  ["$DATA/opencode/state"]="$DATA/local/state/opencode"
)

if [ -f "$MARK" ]; then
  echo "已迁移过（$MARK 存在），跳过。如需重跑先删标记。"
  exit 0
fi

NEED=0
for old in "${!MAP[@]}"; do [ -d "$old" ] && NEED=1; done
if [ "$NEED" = "0" ]; then
  echo "没发现旧版零散卷目录，无需迁移。"
  mkdir -p "$DATA/config" "$DATA/local"
  touch "$MARK"
  exit 0
fi

echo "== 先整体备份 =="
tar -czf "$BASE/data-backup-$STAMP.tgz" -C "$BASE" data
echo "备份完毕: $BASE/data-backup-$STAMP.tgz"

echo "== 迁移 =="
for old in "${!MAP[@]}"; do
  new="${MAP[$old]}"
  [ -d "$old" ] || { echo "跳过（不存在）: $old"; continue; }
  mkdir -p "$new"
  if [ -z "$(ls -A "$new" 2>/dev/null)" ]; then
    cp -a "$old/." "$new/"
    echo "已复制: $old -> $new"
  else
    echo "目标非空，合并缺失文件: $old -> $new"
    cp -an "$old/." "$new/"
  fi
  mv "$old" "$old.bak-$STAMP"
  echo "旧目录已改名保留: $old.bak-$STAMP"
done

# 清理空的旧父目录（仅当空时）
[ -d "$DATA/opencode" ] && [ -z "$(ls -A "$DATA/opencode" 2>/dev/null)" ] && rmdir "$DATA/opencode"

touch "$MARK"
echo "== 完成 =="
echo "确认容器内配置正常后，可手动删除 *.bak-$STAMP 目录和备份包。"
