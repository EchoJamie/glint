#!/usr/bin/env bash
#
# 开发时前台运行 Glint，把诊断输出收进日志文件。
#
# 用途：T0.3 验证候选窗口时需要观察系统会话事件（activateServer /
# deactivateServer / commitComposition）是否按时触达。这些信息走 stderr，
# 而输入法平时由 launchd 拉起，输出没有去处，所以需要这样一个前台运行方式。
#
# **这不是安装，也不能代替安装。** 系统只会连接 ~/Library/Input Methods/
# 下已注册的那份副本；直接跑构建产物只能看到进程自身的启动与诊断，
# 不会有真实输入会话。要拿到真实事件，先 make install 并注册输入源，
# 本脚本会自动优先运行已安装的那份。
#
# 用法：
#   scripts/run-dev.sh           前台运行，Ctrl-C 退出
#   scripts/run-dev.sh --foreground-only   强制运行构建产物
#
# Copyright (C) 2026 EchoJamie <echojamieee@outlook.com>
# This file is part of Glint, licensed under GPLv3 or later. See LICENSE.

set -euo pipefail

cd "$(dirname "$0")/.."

APP_NAME=Glint
INSTALLED="$HOME/Library/Input Methods/$APP_NAME.app/Contents/MacOS/$APP_NAME"
BUILT="build/$APP_NAME.app/Contents/MacOS/$APP_NAME"

if [[ "${1:-}" == "--foreground-only" ]]; then
  BINARY="$BUILT"
elif [[ -x "$INSTALLED" ]]; then
  BINARY="$INSTALLED"
elif [[ -x "$BUILT" ]]; then
  BINARY="$BUILT"
else
  echo "❌ 找不到可执行文件。先执行 make build。" >&2
  exit 1
fi

case "$BINARY" in
  "$INSTALLED")
    echo "运行已安装的副本：$INSTALLED"
    echo "（这是唯一会收到真实输入会话的路径）"
    ;;
  *)
    echo "运行构建产物：$BINARY"
    echo "⚠️  未安装。系统不会把输入会话接到这里，只能看到进程自身的启动与诊断。"
    ;;
esac

LOGDIR=build/logs
mkdir -p "$LOGDIR"
LOG="$LOGDIR/glint-$(date +%Y%m%d-%H%M%S).log"

# 已有同名进程时先提示，避免出现两个实例争同一个连接名。
if pgrep -f "$APP_NAME.app/Contents/MacOS/$APP_NAME" >/dev/null 2>&1; then
  echo "⚠️  检测到已在运行的 Glint 进程。同名连接会造成输入会话行为难以判断。"
  echo "    可先执行：pkill -f '$APP_NAME.app/Contents/MacOS/$APP_NAME'"
fi

echo "日志：$LOG"
echo "另开一个终端查看：tail -f '$LOG'"
echo

# 诊断记录默认只含事件类别与耗时，不含实际输入正文
# （docs/implementation-plan.md §7）。
exec "$BINARY" >"$LOG" 2>&1
