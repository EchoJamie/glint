#!/bin/bash
# 0.1.0 分发盘：输入法、原生安装器与 DMG 使用同一 Apple Development 证书。
# Developer ID 与公证按本次发布约定暂缓，不退回 ad-hoc 签名。
set -euo pipefail
umask 022
cd "$(dirname "$0")/.."

app="$(pwd)/build/Glint.app"
/usr/bin/codesign --verify --strict "$app"
identity="$(/usr/bin/codesign -dv --verbose=4 "$app" 2>&1 | sed -n 's/^Authority=\(Apple Development:.*\)$/\1/p' | head -1)"
expected_identity='Apple Development: echojamieee@outlook.com (9JHY98AJMC)'
if [ "$identity" != "$expected_identity" ]; then
  echo "正式包需要已约定的 Apple Development 证书；当前 App 签名身份不匹配。" >&2
  exit 1
fi
version="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$app/Contents/Info.plist")"
mkdir -p dist
output="$(pwd)/dist/Glint-${version}-arm64.dmg"
temporary="$output.tmp.dmg"
work="$(pwd)/dist/.package"
mkdir "$work"
trap 'rm -rf "$work" "$temporary"' EXIT
stage="$work/volume"
source_stage="$work/source"
mkdir "$stage" "$source_stage"

installer="$stage/安装流光.app"
mkdir -p "$installer/Contents/MacOS" "$installer/Contents/Resources"
DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}" \
  xcrun swiftc -parse-as-library -swift-version 5 -target arm64-apple-macos13.0 -O \
  -o "$installer/Contents/MacOS/GlintInstaller" installer/GlintInstaller.swift sources/App/GlintIds.swift
cp installer/Info.plist "$installer/Contents/Info.plist"
/usr/bin/plutil -replace CFBundleShortVersionString -string "$version" "$installer/Contents/Info.plist"
/usr/bin/plutil -replace CFBundleVersion -string "$version" "$installer/Contents/Info.plist"
cp resources/GlintIcon.icns "$installer/Contents/Resources/"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$app" "$installer/Contents/Resources/Glint.app.zip"
cp scripts/install-user.sh "$installer/Contents/Resources/install-user.sh"
/usr/bin/codesign --force --options runtime --sign "$identity" --timestamp=none "$installer"
/usr/bin/codesign --verify --deep --strict "$installer"

# 对应源码随包提供。预编译组件及预测模型所用的上游源码也按固定摘要收录。
source_cache="$(pwd)/deps/cache/release-source"
mkdir -p "$source_cache" "$source_stage/third-party"
fetch_source() {
  local name="$1" digest="$2" url="$3" file="$source_cache/$1"
  if [ ! -f "$file" ]; then
    curl -fL --retry 2 --silent --show-error -o "$file.part" "$url"
    mv "$file.part" "$file"
  fi
  printf '%s  %s\n' "$digest" "$file" | /usr/bin/shasum -a 256 -c - >/dev/null
  cp "$file" "$source_stage/third-party/$name"
}
fetch_source librime-33e7814.tar.gz d3f48c2c58f718402229031d8d95fde9cac07ababa8fecf7d18b91946f27fee6 \
  https://codeload.github.com/rime/librime/tar.gz/33e78140250125871856cdc5b42ddc6a5fcd3cd4
fetch_source librime-lua-ec52e48.tar.gz 74a10e6c28e1f8d10cf824b46a7ccad49f2f0119796510c29b837d0567277ef0 \
  https://codeload.github.com/hchunhui/librime-lua/tar.gz/ec52e48
fetch_source librime-octagram-dfcc151.tar.gz 27f59e184661408b9c689a8c6840452304695251180907570bfb90baab59c81d \
  https://codeload.github.com/lotem/librime-octagram/tar.gz/dfcc151
fetch_source librime-predict-920bd41.tar.gz 38b2f32254e1a35ac04dba376bc8999915c8fbdb35be489bffdf09079983400c \
  https://codeload.github.com/rime/librime-predict/tar.gz/920bd41ebf6f9bf6855d14fbe80212e54e749791
fetch_source libyaml-0.2.5.tar.gz c642ae9b75fee120b2d96c712538bd2cf283228d2337df2cf2988e3c02678ef4 \
  https://pyyaml.org/download/libyaml/yaml-0.2.5.tar.gz
fetch_source rime-predict-data-1.0.txt df0f7a9ef96569da402d9ea2376aefad4d15382ebcccb05ec84a0acbc00c7f83 \
  https://github.com/rime/librime-predict/releases/download/data-1.0/predict.txt
COPYFILE_DISABLE=1 /usr/bin/tar --no-xattrs --exclude=.DS_Store -cf - \
  Makefile LICENSE README.md THIRD_PARTY.md docs installer licenses resources scripts sources \
  | (cd "$source_stage" && /usr/bin/tar -xf -)
COPYFILE_DISABLE=1 /usr/bin/tar --no-xattrs -czf "$stage/Glint-${version}-source.tar.gz" -C "$source_stage" .
cp scripts/dmg-readme.txt "$stage/安装说明.txt"
/usr/bin/hdiutil create -srcfolder "$stage" -volname "流光" \
  -format UDZO -imagekey zlib-level=9 -ov "$temporary" >/dev/null
/usr/bin/codesign --force --sign "$identity" --timestamp=none "$temporary"
/usr/bin/codesign --verify "$temporary"
/usr/bin/hdiutil verify "$temporary" >/dev/null
mv "$temporary" "$output"
(cd dist && /usr/bin/shasum -a 256 "$(basename "$output")" > SHA256SUMS)
echo "已生成 Glint $version 分发盘：$output"
cat dist/SHA256SUMS
