#!/usr/bin/env bash
#
# 准备**隔离的**测试数据目录。
#
# 数据来源是参考仓库里的 rime-ice（雾凇拼音）检出，不是用户正在使用的
# ~/Library/Rime——plan §5 要求 M0 使用固定测试候选和隔离 Rime 数据，
# 不对现有目录做维护；T0.2 也要求不读取真实个人词条作测试样本。
#
# 目录落在 build/testdata/，已被 .gitignore 排除，可随时删除重建。
#
# Copyright (C) 2026 EchoJamie <echojamieee@outlook.com>
# This file is part of Glint, licensed under GPLv3 or later. See LICENSE.

set -euo pipefail

cd "$(dirname "$0")/.."

REFERENCE=${GLINT_RIME_ICE:-/Users/echo/namespace/github/rime/rime-ice}
DEST=build/testdata/rime

if [[ ! -d "$REFERENCE" ]]; then
  echo "❌ 找不到 rime-ice 参考检出：$REFERENCE" >&2
  echo "   可用 GLINT_RIME_ICE=<路径> 指定。" >&2
  exit 1
fi

# 用户数据目录绝不能是 ~/Library/Rime。
mkdir -p "$(dirname "$DEST")"
ABS_DEST="$(cd "$(dirname "$DEST")" && pwd)/$(basename "$DEST")"
case "$ABS_DEST" in
  "$HOME/Library/Rime"*)
    echo "❌ 拒绝在 $HOME/Library/Rime 下建立测试数据。" >&2
    exit 1
    ;;
esac

echo "建立隔离测试数据：$ABS_DEST"
echo "来源：$REFERENCE"

rm -rf "$DEST"
mkdir -p "$DEST"

# 只复制方案与词库数据，不带 .git。
tar -C "$REFERENCE" --exclude=.git -cf - . | tar -C "$DEST" -xf -

# librime 的部署产物与用户状态一律从零开始，避免混入来源仓库的残留。
rm -rf "$DEST/build" "$DEST/sync"
find "$DEST" -name '*.userdb' -maxdepth 2 -exec rm -rf {} + 2>/dev/null || true
rm -f "$DEST/installation.yaml" "$DEST/user.yaml"

echo "完成。"
echo "  方案：$(ls "$DEST"/*.schema.yaml 2>/dev/null | wc -l | tr -d ' ') 个"
echo "  词库：$(ls "$DEST"/cn_dicts/*.dict.yaml 2>/dev/null | wc -l | tr -d ' ') 个文件"
echo "  大小：$(du -sh "$DEST" | cut -f1)"
echo
echo "注意：这是一份**通用**方案数据，不是用户实际使用的那个版本。"
echo "      基线尚未固定，见 TASKS.md §1.1 的基线缺口。"
