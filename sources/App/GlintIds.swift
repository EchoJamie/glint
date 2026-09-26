// Copyright (C) 2026 EchoJamie <echojamieee@outlook.com>
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// 产品标识的**唯一 Swift 侧来源**。
///
/// `resources/Info.plist` 里必须出现同样的值——系统只从 Info.plist 读取它们，
/// 无法在运行时注入。两处一旦不一致，输入源注册会出现难以定位的问题，
/// 而且**输入源 ID 变更会导致系统内已注册的输入源失效**。
/// `make check-ids` 会核对两边，构建前先跑它。
///
/// 修改前先核对系统登记及 docs/architecture.md 中的产品身份。
enum GlintIds {
  /// 只做简体，不做繁体。后缀 `.Hans` 保留：
  /// 简体模式保留 .Hans 后缀，未来增加其他模式时无需更改已有 ID。
  static let inputSourceID = "com.github.echojamie.inputmethod.Glint.Hans"

  /// 输入源所属的 bundle identifier；顶层 TISInputSourceID 亦用此值。
  ///
  /// **中间段的 `.inputmethod.` 是 IMK 的隐含约定，缺了它系统会静默跳过本输入法。**
  /// 2026-09-25 实测：ID 为 `com.github.echojamie.glint` 时，HIToolbox 的
  /// `TISFileInterrogator` 全量扫描输入法目录，对其它 app 逐个调用
  /// `AddInputMethodAppInfoForCache`，唯独跳过本 app——连 API 都不调、也不报错。
  /// 改成含 `.inputmethod.` 的值后立即被接受，输入源出现在 TIS 清单中。
  /// 对照：鼠须管 `im.rime.inputmethod.Squirrel`、系统 `com.apple.inputmethod.SCIM`。
  /// `macOS_IMKitSample_2021` 的工程要点亦明写「bundle identifier 需包含 .inputmethod.」。
  static let bundleID = "com.github.echojamie.inputmethod.Glint"

  /// 输入源的显示名。中文名见 `CFBundleDisplayName` 的本地化。
  static let displayName = "Glint"

  /// 用户数据目录：`~/Library/Glint`，与 `~/Library/Rime` 同构但完全独立、不共享。
  static let userDataDirectoryName = "Glint"

  /// 安装目录固定为 `~/Library/Input Methods/Glint.app`。
  static var installedAppURL: URL {
    FileManager.default.homeDirectoryForCurrentUser
      .appending(path: "Library/Input Methods/Glint.app", directoryHint: .isDirectory)
  }

  /// 输入服务独占的数据目录；迁移与测试使用各自的独立副本。
  static var userDataURL: URL {
    FileManager.default.homeDirectoryForCurrentUser
      .appending(path: "Library/\(userDataDirectoryName)", directoryHint: .isDirectory)
  }
}
