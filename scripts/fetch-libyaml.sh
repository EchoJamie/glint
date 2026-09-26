#!/usr/bin/env bash
# Copyright (C) 2026 EchoJamie <echojamieee@outlook.com>
# SPDX-License-Identifier: GPL-3.0-or-later
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p deps/downloads deps/yaml/include deps/yaml/lib deps/yaml/obj
archive="deps/downloads/yaml-0.2.5.tar.gz"
if [ ! -f "$archive" ]; then
  curl -fL --retry 2 https://pyyaml.org/download/libyaml/yaml-0.2.5.tar.gz -o "$archive.part"
  mv "$archive.part" "$archive"
fi
printf '%s  %s\n' c642ae9b75fee120b2d96c712538bd2cf283228d2337df2cf2988e3c02678ef4 "$archive" | shasum -a 256 -c -
tar -xzf "$archive" -C deps/yaml
source_dir="deps/yaml/yaml-0.2.5"
for source in "$source_dir"/src/*.c; do
  DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}" xcrun clang \
    -target arm64-apple-macos13.0 -O2 -fPIC -I "$source_dir/include" -I "$source_dir/src" \
    -DYAML_VERSION_MAJOR=0 -DYAML_VERSION_MINOR=2 -DYAML_VERSION_PATCH=5 '-DYAML_VERSION_STRING="0.2.5"' \
    -c "$source" -o "deps/yaml/obj/$(basename "${source%.c}").o"
done
/usr/bin/ar rcs deps/yaml/lib/libyaml.a deps/yaml/obj/*.o
cp "$source_dir/include/yaml.h" deps/yaml/include/
