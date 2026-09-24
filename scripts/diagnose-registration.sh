#!/usr/bin/env bash
#
# 诊断输入源注册为什么没生效。
#
# 核心事实：TISRegisterInputSource 会先查「输入监控」权限，而 TCC 判的是
# **归责对象（responsible process）**——从终端跑就是终端本身，
# Glint 自己拿到多少授权都不参与判定。
#
# 所以本脚本重点回答一个问题：**你现在这个终端，有没有输入监控权限。**
#
# 只用只读查询与一次注册调用，不改任何配置、不需要 sudo。
#
# 用法：scripts/diagnose-registration.sh
#
# Copyright (C) 2026 EchoJamie <echojamieee@outlook.com>
# This file is part of Glint, licensed under GPLv3 or later. See LICENSE.

set -uo pipefail

APP="$HOME/Library/Input Methods/Glint.app"
BIN="$APP/Contents/MacOS/Glint"
TCC_DB="/Library/Application Support/com.apple.TCC/TCC.db"

[[ -x "$BIN" ]] || { echo "❌ 找不到 ${BIN}，先 make install" >&2; exit 1; }

hr() { printf '%s\n' "────────────────────────────────────────────────────"; }

# 当前终端的 bundle id：这是 TCC 会拿来判定的那个
TERM_PID="${TERM_SESSION_ID:-$$}"
CURRENT_TERM=$(osascript -e 'tell application "System Events" to get bundle identifier of first application process whose frontmost is true' 2>/dev/null || echo "")
# 更可靠：沿父进程链找终端应用
ppid=$PPID
while [[ -n "$ppid" && "$ppid" != "1" ]]; do
  exe=$(ps -o comm= -p "$ppid" 2>/dev/null)
  case "$exe" in
    *.app/Contents/MacOS/*)
      CURRENT_TERM=$(printf '%s' "$exe" | sed 's|.*/\([^/]*\)\.app/Contents/MacOS/.*|\1|')
      break ;;
  esac
  ppid=$(ps -o ppid= -p "$ppid" 2>/dev/null | tr -d ' ')
done

hr
echo "① 你现在的终端"
hr
echo "  终端应用: ${CURRENT_TERM:-（未识别）}"

hr
echo "② 授权现状（auth_value: 2=已授予 / 0=拒绝 / 无记录=从未授予）"
hr
sqlite3 "$TCC_DB" \
  "SELECT service, client, auth_value FROM access
   WHERE service IN ('kTCCServiceListenEvent','kTCCServiceAccessibility')
     AND (client LIKE '%glint%' OR client LIKE '%ghostty%' OR client LIKE '%Terminal%'
          OR client LIKE '%iTerm%' OR client LIKE '%Warp%' OR client LIKE '%kitty%'
          OR client LIKE '%WezTerm%' OR client LIKE '%Alacritty%');" 2>/dev/null \
  | sed 's/^/  /' || echo "  （读不了 TCC 库）"

hr
echo "③ 当前包的签名指纹"
hr
codesign -dvvv "$APP" 2>&1 | grep -oE "CDHash=[a-f0-9]+" | head -1 | sed 's/^/  /'

hr
echo "④ 注册并检查"
hr
"$BIN" --install 2>&1 | sed 's/^/  /'
sleep 2
LIST=$("$BIN" --list-input-sources glint 2>&1)
printf '%s\n' "$LIST" | head -4 | sed 's/^/  /'

hr
echo "⑤ 判定"
hr
if printf '%s' "$LIST" | grep -q "没有匹配"; then
  echo "  仍未注册。"
  echo
  echo "  若②里 **${CURRENT_TERM:-你的终端}** 的 kTCCServiceListenEvent 是 2，"
  echo "  说明权限不是症结，需要继续查；"
  echo "  否则请改用 **已有该权限的终端** 重跑本脚本——②里哪个终端是 2 就用哪个。"
else
  echo "  ✅ 已注册：系统认识 com.github.echojamie.glint.Hans"
  echo "     下一步：$BIN --enable-input-source"
fi

echo
echo "看归责对象的原始日志（注册后立刻跑）："
echo "  /usr/bin/log show --last 1m --style compact --info --debug \\"
echo "    --predicate 'process == \"tccd\"' | grep -i glint | grep AUTHREQ_ATTRIBUTION | tail -1"
