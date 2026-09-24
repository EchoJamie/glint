#!/usr/bin/env bash
#
# 核对产品标识在 Info.plist 与 GlintIds.swift 两处一致。
#
# 系统只从 Info.plist 读取标识，无法在运行时注入，因此两处必须手工保持一致。
# 输入源 ID 一旦变更，系统内已注册的输入源会失效（docs/decisions.md 5.4），
# 所以把这件容易忘的事交给构建前的自动检查。
#
# Copyright (C) 2026 EchoJamie <echojamieee@outlook.com>
# This file is part of Glint, licensed under GPLv3 or later. See LICENSE.

set -euo pipefail

cd "$(dirname "$0")/.."

PLIST=resources/Info.plist
SWIFT=sources/GlintIds.swift

fail=0

check() {
  local label=$1 plist_value=$2 swift_value=$3
  if [[ "$plist_value" == "$swift_value" ]]; then
    printf '  ✅ %-24s %s\n' "$label" "$plist_value"
  else
    printf '  ❌ %-24s Info.plist=%s  GlintIds.swift=%s\n' "$label" "$plist_value" "$swift_value"
    fail=1
  fi
}

plist() { /usr/libexec/PlistBuddy -c "Print $1" "$PLIST" 2>/dev/null || echo "(缺失)"; }
swift() { sed -n "s/.*static let $1 = \"\(.*\)\".*/\1/p" "$SWIFT" | head -1; }

echo "核对产品标识（docs/decisions.md 5.4）"
check "bundleID"      "$(plist CFBundleIdentifier)"          "$(swift bundleID)"
check "inputSourceID" "$(plist 'ComponentInputModeDict:tsVisibleInputModeOrderedArrayKey:0')" "$(swift inputSourceID)"

# InputMethodConnectionName 不是随便取的名字，而是**有硬性约定**：
# 必须是 <bundle identifier>_Connection（macOS 10.7 起的 NSConnection 命名约定）。
# 因此这里核对的是这个不变量本身，而不是两个文件里的字面量是否一样——
# decisions.md 5.4 原先定的 Glint_Connection 就不满足它。
bundle_id=$(plist CFBundleIdentifier)
connection=$(plist InputMethodConnectionName)
if [[ "$connection" == "${bundle_id}_Connection" ]]; then
  # 注意用 ${} 界定变量名：后面紧跟全角括号，bash 会把多字节字符
  # 当成变量名的一部分，报 "unbound variable"。
  printf '  ✅ %-24s %s\n' "connectionName" "${connection}（符合 <bundleID>_Connection 约定）"
else
  printf '  ❌ %-24s 实际=%s  应为=%s_Connection\n' "connectionName" "$connection" "$bundle_id"
  echo "     这是 macOS 10.7 起的 NSConnection 硬性约定，不合规会导致输入法加载失败。"
  fail=1
fi

# Info.plist 内部的交叉一致性
declared=$(plist TISInputSourceID)
input=$(plist 'ComponentInputModeDict:tsInputModeListKey:com.github.echojamie.glint.Hans:TISInputSourceID')
if [[ "$declared" == "com.github.echojamie.glint" && "$input" == "com.github.echojamie.glint.Hans" ]]; then
  printf '  ✅ %-24s %s\n' "plist 内部" "$input"
else
  printf '  ❌ %-24s TISInputSourceID=%s  模式=%s\n' "plist 内部" "$declared" "$input"
  fail=1
fi

if [[ $fail -ne 0 ]]; then
  echo
  echo "标识不一致。改之前先更新 docs/decisions.md 5.4 节。"
  exit 1
fi

echo "标识一致。"
