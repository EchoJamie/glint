#!/usr/bin/env bash
#
# 取固定版本的 librime。
#
# 用官方 release 的预编译包，不从源码编译：包内已含 Lua / octagram / predict
# 三个插件，且与 D-02 锁定的 1.17.0 是同一提交。省掉整套 cmake 工具链。
#
# 产物落在 deps/dist/，已在 .gitignore 中排除——依赖不进仓库，
# 由本脚本按固定版本重取，保证可重复构建。
#
# Copyright (C) 2026 EchoJamie <echojamieee@outlook.com>
# This file is part of Glint, licensed under GPLv3 or later. See LICENSE.

set -euo pipefail

cd "$(dirname "$0")/.."

# 引擎版本锁定 1.17.0（D-02）。release tag 与 librime 提交号的对应关系：
#   1.17.0 -> 33e7814（decisions.md 5.1 记录的参考快照同一提交）
RIME_VERSION=1.17.0
RIME_COMMIT=33e7814
ARCHIVE="rime-${RIME_COMMIT}-macOS-universal.tar.bz2"
URL="https://github.com/rime/librime/releases/download/${RIME_VERSION}/${ARCHIVE}"

# 固定校验和：上游未提供，首次取回后记录于此，之后每次核对。
# 上游重新打包会使校验失败——那正是需要人工确认的情况，不要直接改这个值。
SHA256=11d8dc663c6ec06d5ccb6111ba664a9e7b631b703ac6acd07cffbac664021850

DEST=deps/dist
CACHE=deps/cache

mkdir -p "$CACHE" "$DEST"

if [[ ! -f "$CACHE/$ARCHIVE" ]]; then
  echo "下载 librime ${RIME_VERSION}（${RIME_COMMIT}）…"
  curl -fsSL -o "$CACHE/$ARCHIVE.part" "$URL"
  mv "$CACHE/$ARCHIVE.part" "$CACHE/$ARCHIVE"
else
  echo "使用已缓存的 $(basename "$CACHE/$ARCHIVE")"
fi

echo "校验和…"
actual=$(shasum -a 256 "$CACHE/$ARCHIVE" | cut -d' ' -f1)
if [[ "$actual" != "$SHA256" ]]; then
  echo "❌ 校验和不符" >&2
  echo "   期望：$SHA256" >&2
  echo "   实际：$actual" >&2
  echo "   上游可能重新打包。确认来源无误后再更新脚本中的 SHA256。" >&2
  exit 1
fi

echo "解包到 ${DEST}/…"
rm -rf "$DEST"
mkdir -p "$DEST"
# 包内顶层是 dist/ 与 version-info.txt；摊平一层，得到
# deps/dist/{include,lib,bin,share}，避免出现 deps/dist/dist 这样的路径。
tmp=$(mktemp -d)
tar -xjf "$CACHE/$ARCHIVE" -C "$tmp"
mv "$tmp/dist"/* "$DEST"/
[[ -f "$tmp/version-info.txt" ]] && mv "$tmp/version-info.txt" "$DEST"/
rm -rf "$tmp"

echo
echo "librime 就绪："
sed 's/^/  /' "$DEST/version-info.txt"
echo
ls "$DEST/lib/rime-plugins/" | sed 's/^/  插件：/'
