#!/usr/bin/env bash
# Copyright (C) 2026 EchoJamie <echojamieee@outlook.com>
# SPDX-License-Identifier: GPL-3.0-or-later
# 打包全拼、双拼方案与公开词库资源；不打包个人学习库、鼠须管配置或自定义补丁。
set -euo pipefail
cd "$(dirname "$0")/.."

BASELINE=${GLINT_RIME_BASELINE:-$HOME/Desktop/rime-baseline.tar.gz}
REFERENCE=${GLINT_RIME_ICE:-$HOME/namespace/github/rime/rime-ice}
mkdir -p build
STAGING=$(mktemp -d build/bundled-rime.XXXXXX)
trap 'rm -rf "$STAGING"' EXIT

python3 - "$BASELINE" "$REFERENCE" "$STAGING" <<'PY'
import hashlib
from pathlib import Path, PurePosixPath
import shutil
import sys
import tarfile

baseline, reference, staging = map(Path, sys.argv[1:])
schemas = {'rime_ice', 'melt_eng', 'radical_pinyin'}
schemas.update({'double_pinyin', 'double_pinyin_abc', 'double_pinyin_flypy',
                'double_pinyin_jiajia', 'double_pinyin_mspy',
                'double_pinyin_sogou', 'double_pinyin_ziguang'})
folders = {'cn_dicts', 'en_dicts', 'lua', 'opencc'}

def included(name):
    path = PurePosixPath(name)
    if path.is_absolute() or '..' in path.parts or any(p.startswith('.') for p in path.parts):
        return False
    if len(path.parts) > 1:
        return path.parts[0] in folders and not any('.userdb' in p for p in path.parts)
    if name == 'rime.lua':
        return True
    if not name.endswith('.yaml') or name.endswith('.custom.yaml'):
        return False
    if name in {'squirrel.yaml', 'weasel.yaml', 'installation.yaml', 'user.yaml'}:
        return False
    if name.endswith('.schema.yaml'):
        return name.removesuffix('.schema.yaml') in schemas
    return True

if baseline.is_file():
    print(f'来源：基线包 {baseline}，sha256={hashlib.sha256(baseline.read_bytes()).hexdigest()}')
    with tarfile.open(baseline) as archive:
        for member in archive:
            name = str(PurePosixPath(member.name))
            if not member.isfile() or not included(name):
                continue
            target = staging / name
            target.parent.mkdir(parents=True, exist_ok=True)
            with archive.extractfile(member) as src, target.open('wb') as dst:
                shutil.copyfileobj(src, dst)
elif reference.is_dir():
    print(f'来源：参考检出 {reference}（开发数据）')
    for source in reference.rglob('*'):
        name = source.relative_to(reference).as_posix()
        if source.is_file() and not source.is_symlink() and included(name):
            target = staging / name
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(source, target)
else:
    raise SystemExit('找不到基线包或 rime-ice 检出；请设置 GLINT_RIME_BASELINE 或 GLINT_RIME_ICE。')

required = ['default.yaml'] + [s + '.schema.yaml' for s in schemas]
required += [s + '.dict.yaml' for s in ('rime_ice', 'melt_eng', 'radical_pinyin')]
missing = [name for name in required if not (staging / name).is_file()]
missing += [name for name in folders if not (staging / name).is_dir()]
if missing:
    raise SystemExit('方案资源不完整：' + ', '.join(missing))

shutil.copyfile('deps/dist/share/glint/glint-predict.db', staging / 'glint-predict.db')
(staging / 'default.custom.yaml').write_text('''# Glint 默认中文，英文使用系统 ABC；Caps Lock 长短按由 macOS 处理。
patch:
  schema_list:
    - schema: rime_ice
  "ascii_composer/switch_key/Shift_L": noop
  "ascii_composer/switch_key/Shift_R": noop
''')
manifest = '\n'.join(f'{hashlib.sha256(p.read_bytes()).hexdigest()}  {p.relative_to(staging)}'
                     for p in sorted(staging.rglob('*')) if p.is_file())
(staging / 'data-manifest.sha256').write_text(manifest + '\n')
(staging / '.ready').touch()
print(f'已准备 {len(manifest.splitlines())} 个资源文件，含逐文件校验清单。')
PY

# 完整准备成功后才替换生成目录；失败保留上一份可构建数据。
rm -rf build/bundled-rime
mv "$STAGING" build/bundled-rime
echo '完成：build/bundled-rime；make build 会在签名前嵌入。'
