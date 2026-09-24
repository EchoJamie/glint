#!/usr/bin/env bash
#
# 最小输入法包实验：把 Info.plist 削到只剩必需键，看系统认不认。
#
# 目的：如果最小包能注册 → 我们的 Info.plist 里有某个键在毒害注册，二分定位。
#       如果最小包也不注册 → 问题不在 Info.plist，在更底层（包结构 / 可执行文件 / 系统）。
#
# 用不同的 bundle id 与连接名，避免与正式包冲突。
# 用完即删，不进产物、不影响正式安装。
#
# 用法：scripts/bisect-bundle.sh [info | full]
#   info  只放必需键的最小 Info.plist
#   full  用正式包的 Info.plist（对照）
#
# Copyright (C) 2026 EchoJamie <echojamieee@outlook.com>
# This file is part of Glint, licensed under GPLv3 or later. See LICENSE.

set -euo pipefail

cd "$(dirname "$0")/.."

MODE="${1:-info}"
TESTID="com.github.echojamie.glintmin"
TESTAPP="$HOME/Library/Input Methods/GlintMin.app"
SRC="build/Glint.app"

[[ -d "$SRC" ]] || { echo "❌ 先 make build" >&2; exit 1; }

echo "构建最小测试包（模式：${MODE}）"
rm -rf "$TESTAPP"
mkdir -p "$TESTAPP/Contents/MacOS"

cp "$SRC/Contents/MacOS/Glint" "$TESTAPP/Contents/MacOS/Glint"
# 可执行文件链接了 @rpath/librime.1.dylib，缺了它进程起不来，
# 注册也就无从谈起（第一次跑就栽在这儿）。
cp -R "$SRC/Contents/Frameworks" "$TESTAPP/Contents/"

if [[ "$MODE" == "full" ]]; then
  cp "$SRC/Contents/Info.plist" "$TESTAPP/Contents/Info.plist"
  # 换成测试包自己的标识，但仍走同样的结构
  /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $TESTID" "$TESTAPP/Contents/Info.plist"
  /usr/libexec/PlistBuddy -c "Set :InputMethodConnectionName ${TESTID}_Connection" "$TESTAPP/Contents/Info.plist"
  /usr/libexec/PlistBuddy -c "Set :TISInputSourceID $TESTID" "$TESTAPP/Contents/Info.plist"
  /usr/libexec/PlistBuddy -c "Set :ComponentInputModeDict:tsVisibleInputModeOrderedArrayKey:0 ${TESTID}.Hans" "$TESTAPP/Contents/Info.plist"
  /usr/libexec/PlistBuddy -c "Set :ComponentInputModeDict:tsInputModeListKey:${TESTID}.Hans/TISInputSourceID ${TESTID}.Hans" \
    "$TESTAPP/Contents/Info.plist" 2>/dev/null || true
else
  # 最小集合：只放 InputMethodKit 输入法必需的键。
  cat > "$TESTAPP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key><string>en</string>
	<key>CFBundleExecutable</key><string>Glint</string>
	<key>CFBundleIdentifier</key><string>${TESTID}</string>
	<key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
	<key>CFBundleName</key><string>GlintMin</string>
	<key>CFBundlePackageType</key><string>APPL</string>
	<key>CFBundleSignature</key><string>????</string>
	<key>CFBundleVersion</key><string>0.1.0</string>
	<key>LSBackgroundOnly</key><false/>
	<key>LSUIElement</key><true/>
	<key>NSPrincipalClass</key><string>NSApplication</string>
	<key>TISInputSourceID</key><string>${TESTID}</string>
	<key>InputMethodConnectionName</key><string>${TESTID}_Connection</string>
	<key>InputMethodServerControllerClass</key><string>Glint.GlintInputController</string>
	<key>ComponentInputModeDict</key>
	<dict>
		<key>tsInputModeListKey</key>
		<dict>
			<key>${TESTID}.Hans</key>
			<dict>
				<key>TISInputSourceID</key><string>${TESTID}.Hans</string>
				<key>TISIntendedLanguage</key><string>zh-Hans</string>
				<key>tsInputModeIsVisibleKey</key><true/>
				<key>tsInputModePrimaryInScriptKey</key><true/>
				<key>tsInputModeScriptKey</key><string>smUnicodeScript</string>
			</dict>
		</dict>
		<key>tsVisibleInputModeOrderedArrayKey</key>
		<array><string>${TESTID}.Hans</string></array>
	</dict>
</dict>
</plist>
PLIST
fi

printf 'APPL????' > "$TESTAPP/Contents/PkgInfo"
plutil -lint "$TESTAPP/Contents/Info.plist" >/dev/null

IDENT=$(security find-identity -v -p codesigning 2>/dev/null \
        | sed -n 's/.*"\(Apple Development:.*\)"/\1/p' | head -1)
codesign --force --options runtime \
  --entitlements resources/Glint.entitlements \
  --sign "$IDENT" --timestamp=none "$TESTAPP" >/dev/null 2>&1
echo "  已签名：${IDENT:-ad-hoc}"

echo
echo "注册并检查："
"$TESTAPP/Contents/MacOS/Glint" --install >/dev/null 2>&1 || true
sleep 1
"$TESTAPP/Contents/MacOS/Glint" --list-input-sources glintmin 2>&1 | head -3

echo
echo "试完清理：rm -rf '$TESTAPP'"
