#!/usr/bin/env bash
# Copyright (C) 2026 EchoJamie <echojamieee@outlook.com>
# SPDX-License-Identifier: GPL-3.0-or-later
# 只读核对安装、签名、输入源枚举与近期 Glint 日志。不重新登记或修改系统偏好。
set -euo pipefail
APP="$HOME/Library/Input Methods/Glint.app"
BIN="$APP/Contents/MacOS/Glint"
[[ -x "$BIN" ]] || { echo "未安装：$APP" >&2; exit 1; }
/usr/bin/codesign --verify --strict "$APP"
"$BIN" --list-input-sources glint
if [[ -f "$HOME/Library/Glint/logs/glint.log" ]]; then
  /usr/bin/tail -n 80 "$HOME/Library/Glint/logs/glint.log"
fi
/usr/bin/log show --last 5m --style compact --info \
  --predicate 'subsystem == "com.github.echojamie.inputmethod.Glint"'
echo '上述结果仅证明对应层的状态；真实输入还需看宿主预编辑、候选和提交。'
