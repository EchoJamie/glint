#!/usr/bin/env bash
# Copyright (C) 2026 EchoJamie <echojamieee@outlook.com>
# SPDX-License-Identifier: GPL-3.0-or-later
# 只在构建机取工具头文件；应用只附带生成的约 7 MB 简体预测数据。
set -euo pipefail
cd "$(dirname "$0")/.."
cache="$PWD/deps/cache/prediction"
work="$PWD/deps/build/prediction"
output="$PWD/deps/dist/share/glint"
mkdir -p "$cache" "$work" "$output"
fetch() {
  local name="$1" digest="$2" url="$3"
  if [[ ! -f "$cache/$name" ]]; then
    curl -fL --retry 2 "$url" -o "$cache/$name.part"
    mv "$cache/$name.part" "$cache/$name"
  fi
  [[ "$(shasum -a 256 "$cache/$name" | cut -d ' ' -f 1)" == "$digest" ]] || {
    echo "预测资源校验失败：$name" >&2; exit 1;
  }
}
fetch predict.txt df0f7a9ef96569da402d9ea2376aefad4d15382ebcccb05ec84a0acbc00c7f83 \
  https://github.com/rime/librime-predict/releases/download/data-1.0/predict.txt
fetch librime.tar.gz d3f48c2c58f718402229031d8d95fde9cac07ababa8fecf7d18b91946f27fee6 \
  https://codeload.github.com/rime/librime/tar.gz/33e78140250125871856cdc5b42ddc6a5fcd3cd4
fetch predict.tar.gz 38b2f32254e1a35ac04dba376bc8999915c8fbdb35be489bffdf09079983400c \
  https://codeload.github.com/rime/librime-predict/tar.gz/920bd41ebf6f9bf6855d14fbe80212e54e749791
fetch marisa.tar.gz c24516edc43be8049ef4e23e50a574d4670036fe3595c49c0f01d4d87ce58f57 \
  https://codeload.github.com/s-yata/marisa-trie/tar.gz/3e87d53b78e15f2f43783d5e376561a8c9722051
fetch boost.tar.bz2 7009fe1faa1697476bdc7027703a2badb84e849b7b0baad5086b087b971f8617 \
  https://archives.boost.io/release/1.85.0/source/boost_1_85_0.tar.bz2
for source in librime predict marisa; do
  mkdir -p "$work/$source"
  tar -xzf "$cache/$source.tar.gz" -C "$work/$source" --strip-components=1
done
tar -xjf "$cache/boost.tar.bz2" -C "$work" boost_1_85_0/boost
mkdir -p "$work/include/rime"
# 工具使用不带日志宏的官方头文件；运行库与插件仍为 fetch-librime.sh 的固定版本。
touch "$work/include/rime/build_config.h"
xcrun clang++ -std=c++17 -I "$work/include" -I "$work/librime/src" -I "$work/librime/include" \
  -I "$work/marisa/include" -I "$work/boost_1_85_0" -I "$work/predict/src" \
  "$work/predict/tools/build_predict.cc" "$PWD/deps/dist/lib/rime-plugins/librime-predict.dylib" \
  -L "$PWD/deps/dist/lib" -lrime -Wl,-rpath,"$PWD/deps/dist/lib" \
  -Wl,-rpath,"$PWD/deps/dist/lib/rime-plugins" -o "$work/build_predict"
xcrun swift scripts/simplify-prediction.swift "$cache/predict.txt" "$work/predict-simplified.txt"
"$work/build_predict" "$output/glint-predict.db.tmp" < "$work/predict-simplified.txt"
mv "$output/glint-predict.db.tmp" "$output/glint-predict.db"
shasum -a 256 "$output/glint-predict.db"
