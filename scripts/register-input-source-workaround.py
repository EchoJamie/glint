#!/usr/bin/env python3
#
# 手工把 Glint 登记进 com.apple.HIToolbox 的 AppleEnabledInputSources。
#
# **这是一个 workaround，针对 macOS 26/27 的一个失效。**
#
# 正常安装时，系统会自己把输入法写进这份偏好。但在 macOS 26/27 上这一步坏了：
# 第三方输入法即使 Info.plist 声明正确、签名与公证有效，也不会出现在
# AppleEnabledInputSources 里（先例：WeType 2.1.0，Homebrew cask #264600，
# 症状与我们逐条吻合）。社区给出的处理办法就是手工补登记。
#
# 官方途径是注销重登——但本机已实测无效。
#
# **代价与风险**：
#   - 会改用户的输入源清单。因此本脚本强制先备份、写回前校验、写回后复核。
#   - 系统更新可能重置这份偏好，届时需要重跑。
#   - 这是绕过系统坏行为，不是正规做法。Apple 修好后本脚本即可废弃。
#
# 用法：
#   scripts/register-input-source-workaround.py           执行（自动备份）
#   scripts/register-input-source-workaround.py --revert  还原最近一次备份
#   scripts/register-input-source-workaround.py --dry-run 只看会改什么
#
# 恢复通道（从另一台机器 SSH 过来执行，不依赖本机输入系统）：
#   defaults import com.apple.HIToolbox <备份文件>
#   killall cfprefsd TextInputMenuAgent TextInputSwitcher
#
# Copyright (C) 2026 EchoJamie <echojamieee@outlook.com>
# This file is part of Glint, licensed under GPLv3 or later. See LICENSE.

import argparse
import plistlib
import subprocess
import sys
import time
from pathlib import Path

DOMAIN = "com.apple.HIToolbox"
BUNDLE_ID = "com.github.echojamie.glint"
INPUT_MODE = f"{BUNDLE_ID}.Hans"

ROOT = Path(__file__).resolve().parent.parent
BACKUP_DIR = ROOT / "build" / "rollback"


def read_domain():
    """读出整个偏好域。失败直接退出——读不到就不该写。"""
    result = subprocess.run(
        ["defaults", "export", DOMAIN, "-"], capture_output=True)
    if result.returncode != 0:
        raise SystemExit(f"读不到 {DOMAIN}：{result.stderr.decode(errors='replace')}")
    return plistlib.loads(result.stdout)


def write_domain(plist):
    """写回整个偏好域。写前先自校验，避免把坏数据灌进去。"""
    data = plistlib.dumps(plist)          # 序列化失败会在这里抛异常
    plistlib.loads(data)                  # 反序列化一遍，确认真的可读
    tmp = BACKUP_DIR / f".{DOMAIN}.new.plist"
    tmp.write_bytes(data)
    result = subprocess.run(["defaults", "import", DOMAIN, str(tmp)],
                            capture_output=True)
    tmp.unlink(missing_ok=True)
    if result.returncode != 0:
        raise SystemExit(f"写入失败：{result.stderr.decode(errors='replace')}")


def wanted_entries():
    """父级 + 模式，两条都要。

    参考现有条目：苹果自己的输入法也是两条——
      {"Bundle ID": "com.apple.inputmethod.SCIM", "InputSourceKind": "Keyboard Input Method"}
      {"Bundle ID": "com.apple.inputmethod.SCIM", "Input Mode": "...ITABC", "InputSourceKind": "Input Mode"}
    只加父级或只加模式都不够。
    """
    return [
        {"Bundle ID": BUNDLE_ID, "InputSourceKind": "Keyboard Input Method"},
        {"Bundle ID": BUNDLE_ID, "Input Mode": INPUT_MODE, "InputSourceKind": "Input Mode"},
    ]


def contains(sources, item):
    return any(all(s.get(k) == v for k, v in item.items()) for s in sources)


def restart_agents():
    for agent in ("cfprefsd", "TextInputMenuAgent", "TextInputSwitcher"):
        subprocess.run(["killall", agent], capture_output=True)
    time.sleep(2)


def apply(dry_run):
    plist = read_domain()
    sources = list(plist.get("AppleEnabledInputSources", []))
    before = len(sources)

    added = [e for e in wanted_entries() if not contains(sources, e)]
    print(f"现有输入源 {before} 条；需要追加 {len(added)} 条")
    for e in added:
        print(f"   + {e}")
    if not added:
        print("两条都已存在，无需改动。")
        return 0

    if dry_run:
        print("\n（--dry-run，未写入）")
        return 0

    # 备份
    BACKUP_DIR.mkdir(parents=True, exist_ok=True)
    stamp = time.strftime("%Y%m%d-%H%M%S")
    backup = BACKUP_DIR / f"{DOMAIN}.{stamp}.plist"
    backup.write_bytes(plistlib.dumps(plist))
    print(f"\n已备份到 {backup.relative_to(ROOT)}")

    sources.extend(added)
    plist["AppleEnabledInputSources"] = sources
    write_domain(plist)

    # 复核：条数对，且原有条目一条不少
    check = read_domain()
    after = check.get("AppleEnabledInputSources", [])
    original_intact = all(contains(after, e)
                          for e in plist.get("AppleEnabledInputSources", [])[:before])
    if len(after) != before + len(added) or not original_intact:
        print(f"\n❌ 复核未通过：期望 {before + len(added)} 条，实际 {len(after)} 条"
              f"（原有条目完整={original_intact}）")
        print(f"   立即还原：defaults import {DOMAIN} {backup}")
        return 1

    print(f"✅ 已写入，复核通过：{before} → {len(after)} 条，原有条目全部保留")

    print("\n重启输入源代理…")
    restart_agents()

    print("\n验证：")
    binary = Path.home() / "Library/Input Methods/Glint.app/Contents/MacOS/Glint"
    if binary.exists():
        subprocess.run([str(binary), "--list-input-sources", "glint"])
    print(f"\n还原命令：\n  defaults import {DOMAIN} {backup}\n"
          f"  killall cfprefsd TextInputMenuAgent TextInputSwitcher")
    return 0


def revert():
    backups = sorted(BACKUP_DIR.glob(f"{DOMAIN}.*.plist"))
    if not backups:
        raise SystemExit(f"找不到备份：{BACKUP_DIR}/{DOMAIN}.*.plist")
    latest = backups[-1]
    print(f"从 {latest.name} 还原…")
    subprocess.run(["defaults", "import", DOMAIN, str(latest)], check=True)
    restart_agents()
    plist = read_domain()
    print(f"✅ 已还原，当前 {len(plist.get('AppleEnabledInputSources', []))} 条输入源")
    return 0


def main():
    parser = argparse.ArgumentParser(description="手工登记 Glint 输入源（macOS 26/27 workaround）")
    parser.add_argument("--revert", action="store_true", help="从最近一次备份还原")
    parser.add_argument("--dry-run", action="store_true", help="只看会改什么，不写入")
    args = parser.parse_args()
    BACKUP_DIR.mkdir(parents=True, exist_ok=True)
    return revert() if args.revert else apply(args.dry_run)


if __name__ == "__main__":
    sys.exit(main())
