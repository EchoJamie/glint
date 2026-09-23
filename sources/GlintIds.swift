//
//  GlintIds.swift
//  Glint
//
//  Copyright (C) 2026 EchoJamie <echojamieee@outlook.com>
//
//  This file is part of Glint, licensed under the GNU General Public License
//  version 3 or later. See LICENSE in the project root.
//

import Foundation

/// 产品标识的**唯一 Swift 侧来源**。
///
/// `resources/Info.plist` 里必须出现同样的值——系统只从 Info.plist 读取它们，
/// 无法在运行时注入。两处一旦不一致，输入源注册会出现难以定位的问题，
/// 而且**输入源 ID 变更会导致系统内已注册的输入源失效**。
/// `make check-ids` 会核对两边，构建前先跑它。
///
/// 取值依据：`docs/decisions.md` 5.4 节。修改前先改那份文档。
enum GlintIds {
  /// 只做简体，不做繁体。后缀 `.Hans` 保留：
  /// 日后若要加繁体，保留后缀意味着不必改 ID（见 decisions.md 5.4）。
  static let inputSourceID = "com.github.echojamie.glint.Hans"

  /// 输入源所属的 bundle identifier；顶层 TISInputSourceID 亦用此值。
  static let bundleID = "com.github.echojamie.glint"

  /// Info.plist 的 `InputMethodConnectionName`。
  static let connectionName = "Glint_Connection"

  /// 输入源的显示名。中文名见 `CFBundleDisplayName` 的本地化。
  static let displayName = "Glint"

  /// 用户数据目录：`~/Library/Glint`，与 `~/Library/Rime` 同构但完全独立、不共享。
  static let userDataDirectoryName = "Glint"

  /// 安装目录固定为 `~/Library/Input Methods/Glint.app`。
  static var installedAppURL: URL {
    FileManager.default.homeDirectoryForCurrentUser
      .appending(path: "Library/Input Methods/Glint.app", directoryHint: .isDirectory)
  }

  /// 用户数据目录。M0 阶段仅建立常量，尚未使用——Rime 接入在 T0.2。
  static var userDataURL: URL {
    FileManager.default.homeDirectoryForCurrentUser
      .appending(path: "Library/\(userDataDirectoryName)", directoryHint: .isDirectory)
  }
}
