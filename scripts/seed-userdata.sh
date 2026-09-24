#!/usr/bin/env bash
#
# 把隔离测试数据放进真实用户数据目录 ~/Library/Glint。
#
# **这是开发手段，不是产品的首次部署方式。**
#
# 正常的产品形态应当是随包附带方案数据、首次运行时部署（Squirrel 就是这么做的），
# 那属于 M1 的「全拼资源」范围。现在还不能这么做，因为**具体采用的方案与版本
# 仍未固定**——本机 clone 的是 rime-ice 的今天 main，不是用户实际在用的那份
# （见 TASKS.md §1.1 的基线缺口）。先固定版本再随包，否则会把错误的基线固化进产物。
#
# 在此之前，用这份通用方案数据让已安装的输入法能出候选，以便验证 T0.3
# 的候选窗口。等基线确定后本脚本应被废弃。
#
# 用法：
#   scripts/seed-userdata.sh          播种（目标非空时会拒绝）
#   scripts/seed-userdata.sh --force  覆盖已存在的目标
#
# Copyright (C) 2026 EchoJamie <echojamieee@outlook.com>
# This file is part of Glint, licensed under GPLv3 or later. See LICENSE.

set -euo pipefail

cd "$(dirname "$0")/.."

SOURCE=build/testdata/rime
TARGET="$HOME/Library/Glint"
FORCE=0
[[ "${1:-}" == "--force" ]] && FORCE=1

if [[ ! -d "$SOURCE" ]]; then
  echo "❌ 找不到 ${SOURCE}。先执行 make testdata。" >&2
  exit 1
fi

# 绝不写进 ~/Library/Rime——那是鼠须管的数据，本产品与它完全独立。
case "$TARGET" in
  "$HOME/Library/Rime"*)
    echo "❌ 拒绝写入 ${TARGET}。" >&2
    exit 1
    ;;
esac

if [[ -e "$TARGET" ]] && [[ $FORCE -eq 0 ]]; then
  echo "⚠️  $TARGET 已存在，未改动。" >&2
  echo "    确认要覆盖请加 --force。" >&2
  exit 1
fi

echo "播种用户数据目录：$TARGET"
echo "来源（通用测试数据，非用户实际使用的版本）：$SOURCE"
mkdir -p "$TARGET"
tar -C "$SOURCE" --exclude=build -cf - . | tar -C "$TARGET" -xf -
rm -rf "$TARGET/build" "$TARGET/sync"
find "$TARGET" -maxdepth 2 -name '*.userdb' -exec rm -rf {} + 2>/dev/null || true

echo "完成。"
echo
echo "⚠️  这是 rime-ice 的当前 main，不是实际使用的那份。"
echo "    固定基线后应改用真实版本，并改为随包附带 + 首次运行部署。"
echo
echo "移除：rm -rf ~/Library/Glint"
