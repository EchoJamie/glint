//
//  KeyCodes.swift
//  Glint
//
//  Copyright (C) 2026 EchoJamie <echojamieee@outlook.com>
//
//  This file is part of Glint, licensed under the GNU General Public License
//  version 3 or later. See LICENSE in the project root.
//

/// librime 的键码。
///
/// **这不是 macOS 的虚拟键码。** librime 沿用 IBus / X11 的键码约定：
/// 可打印 ASCII 直接用其码值（`n` 是 110，不是 45），其余用 `XK_*`。
/// 直接把 `NSEvent.keyCode` 交给 `process_key` 会得到看似「部分按键被接收」
/// 的怪异现象——因为那些数字恰好也是别的字符的键码。完整的 macOS →
/// Rime 映射见参考实现 `sources/MacOSKeyCodes.swift`，按实施计划 §3 在 M1
/// 处理真实按键时复用；这里只放离线用例够用的那一部分，不手抄整张表。
enum RimeKey {
  /// 小写字母的键码就是其 ASCII 值。
  static func letter(_ character: Character) -> UInt32? {
    guard let scalar = character.unicodeScalars.first,
          character.isLowercase,
          scalar.isASCII,
          (97...122).contains(scalar.value)
    else { return nil }
    return scalar.value
  }

  /// `XK_space`，同时也是 ASCII 空格。
  static let space: UInt32 = 0x20
  /// `XK_Return`
  static let ret: UInt32 = 0xff0d
  /// `XK_Escape`
  static let escape: UInt32 = 0xff1b

  /// 修饰键掩码，与 `rime/modifier.h` 一致。
  enum Modifier {
    static let shift: UInt32 = 1 << 0
    static let lock: UInt32 = 1 << 1
    static let control: UInt32 = 1 << 2
    static let alt: UInt32 = 1 << 3
    static let superKey: UInt32 = 1 << 26
  }
}
