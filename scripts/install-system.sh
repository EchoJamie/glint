#!/usr/bin/env bash
#
# 系统级安装：装到 /Library/Input Methods/Glint.app。
#
# **为什么要试这个位置**：decisions.md 5.4 定的是用户级
# `~/Library/Input Methods/Glint.app`，在那里注册后本机需要注销才生效。
# 而参考实现鼠须管装的是**系统级** `/Library/Input Methods/Squirrel.app`
# （见其 Makefile 的 `DSTROOT = /Library/Input Methods`），用户的经验是
# 装完立即生效、无需注销。两者路径不同，本脚本用于验证这是否就是差异所在。
#
# 验证通过后需要回头修订 decisions.md 5.4 的安装目录——那是用户已确认的决定，
# 不能由本脚本自行改写。
#
# 需要 sudo。注册与启用按鼠须管的做法以**登录用户**身份执行，不是 root。
#
# Copyright (C) 2026 EchoJamie <echojamieee@outlook.com>
# This file is part of Glint, licensed under GPLv3 or later. See LICENSE.

set -euo pipefail

cd "$(dirname "$0")/.."

APP_NAME=Glint
SOURCE="build/$APP_NAME.app"
DEST="/Library/Input Methods"

if [[ ! -d "$SOURCE" ]]; then
  echo "❌ 找不到 $SOURCE。先执行 make build。" >&2
  exit 1
fi

echo "系统级安装到 $DEST/$APP_NAME.app"
echo "（会提示输入密码；用户级那份保持不变）"
echo

sudo rm -rf "$DEST/$APP_NAME.app"
sudo cp -R "$SOURCE" "$DEST/"

echo
echo "注册输入源（以当前登录用户身份，与鼠须管的做法一致）…"
"$DEST/$APP_NAME.app/Contents/MacOS/$APP_NAME" --install

echo
echo "系统是否已认识这个输入源："
"$DEST/$APP_NAME.app/Contents/MacOS/$APP_NAME" --list-input-sources glint

echo
echo "若上面列出了 com.github.echojamie.glint.Hans，说明系统级安装**无需注销即生效**，"
echo "那就与鼠须管的行为一致，decisions.md 5.4 的安装目录需要重新决定。"
echo
echo "卸载：sudo rm -rf '$DEST/$APP_NAME.app'"
