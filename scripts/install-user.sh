#!/bin/bash
# 用户级安装：先校验完整副本，再替换；旧包仅暂存至替换完成。
set -euo pipefail
script_dir="$(cd "$(dirname "$0")" && pwd)"
source_bundle="${1:-$(cd "$script_dir/.." && pwd)/build/Glint.app}"
if [ ! -d "$source_bundle" ]; then
  echo "找不到输入法程序：$source_bundle" >&2
  exit 1
fi
install_root="${GLINT_INSTALL_ROOT:-$HOME/Library/Input Methods}"
target="$install_root/Glint.app"
mkdir -p "$install_root"
staging="$(mktemp -d "$install_root/.glint-install-XXXXXX")"
backup="$staging/previous"
finish_installation() {
  status=$?
  if [ -e "$backup" ] && [ ! -e "$target" ]; then
    if ! mv "$backup" "$target"; then
      echo "旧程序未能恢复，请保留暂存目录：$staging" >&2
      return 1
    fi
    echo "安装失败，旧包已恢复。" >&2
  fi
  # 成功后删除旧包；恢复失败时保留。暂存件不使用 .app 后缀。
  rm -rf "$staging" || return 1
  return "$status"
}
trap finish_installation EXIT
/usr/bin/ditto "$source_bundle" "$staging/payload"
/usr/bin/codesign --verify --strict "$staging/payload"
/usr/bin/cmp "$source_bundle/Contents/MacOS/Glint" "$staging/payload/Contents/MacOS/Glint"
if [ -e "$target" ]; then
  mv "$target" "$backup"
fi
mv "$staging/payload" "$target"
echo "已安装：$target"
echo "个人词库、设置及已下载方案均保留。"
