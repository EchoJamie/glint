#!/usr/bin/env bash
#
# 核对产品标识在 Info.plist 与 GlintIds.swift 两处一致。
#
# 系统只从 Info.plist 读取标识，无法在运行时注入，因此两处必须手工保持一致。
# 输入源 ID 一旦变更，系统内已注册的输入源会失效（docs/troubleshooting.md），
# 所以把这件容易忘的事交给构建前的自动检查。
#
# Copyright (C) 2026 EchoJamie <echojamieee@outlook.com>
# This file is part of Glint, licensed under GPLv3 or later. See LICENSE.

set -euo pipefail

cd "$(dirname "$0")/.."

PLIST=resources/Info.plist
SWIFT=sources/App/GlintIds.swift

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

echo "核对产品标识"
check "bundleID"      "$(plist CFBundleIdentifier)"          "$(swift bundleID)"
check "inputSourceID" "$(plist 'ComponentInputModeDict:tsVisibleInputModeOrderedArrayKey:0')" "$(swift inputSourceID)"

# Info.plist 内部的交叉一致性
declared=$(plist TISInputSourceID)
input=$(plist 'ComponentInputModeDict:tsInputModeListKey:com.github.echojamie.inputmethod.Glint.Hans:TISInputSourceID')
if [[ "$declared" == "com.github.echojamie.inputmethod.Glint" && "$input" == "com.github.echojamie.inputmethod.Glint.Hans" ]]; then
  printf '  ✅ %-24s %s\n' "plist 内部" "$input"
else
  printf '  ❌ %-24s TISInputSourceID=%s  模式=%s\n' "plist 内部" "$declared" "$input"
  fail=1
fi

if [[ $fail -ne 0 ]]; then
  echo
  echo "标识不一致。改之前先核对 docs/architecture.md 和系统登记的输入源。"
  exit 1
fi

echo "标识一致。"
