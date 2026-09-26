#!/usr/bin/env bash
# Copyright (C) 2026 EchoJamie <echojamieee@outlook.com>
# SPDX-License-Identifier: GPL-3.0-or-later
# 观察已运行输入法的文件日志；不启动第二个实例争用同一个 IMK 连接。
set -euo pipefail
exec /usr/bin/tail -n 40 -F "$HOME/Library/Glint/logs/glint.log"
