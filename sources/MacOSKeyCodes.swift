//
//  MacOSKeyCodes.swift
//  Glint
//
//  Copyright (C) 2026 EchoJamie <echojamieee@outlook.com>
//
//  This file is part of Glint, licensed under the GNU General Public License
//  version 3 or later. See LICENSE in the project root.
//
//  ---------------------------------------------------------------------------
//  来源：本文件**复用并修改**自 鼠须管（Squirrel）@
//  0cd71a6130a5866b0ae6ba0494929ebdc8211194 的 `sources/MacOSKeyCodes.swift`
//  （GPLv3，Copyright (C) RIME Developers / Leo Liu）。
//  本项目同为 GPLv3，复用与修改依据 decisions.md 5.2 节登记；
//  修改内容见文件末尾「与参考实现的差异」。
//  ---------------------------------------------------------------------------
//

import AppKit
import Carbon

/// macOS 虚拟键码 → librime 键码的转换。
///
/// librime 用的是 **IBus / X11 的键码约定**，不是 macOS 的虚拟键码。
/// 两者数值完全不同：字母 `n` 的 macOS 键码是 45，而 librime 要的是 110（ASCII）。
/// 直接传 macOS 键码会被引擎当成别的字符，表现为「部分按键被接受」这种难查的现象。
enum MacOSKeyCode {

  // MARK: - 修饰键

  /// `NSEvent.ModifierFlags` → librime 的修饰键掩码。
  static func rimeModifiers(from modifiers: NSEvent.ModifierFlags) -> UInt32 {
    var result: UInt32 = 0
    if modifiers.contains(.capsLock) { result |= RimeModifier.lock }
    if modifiers.contains(.shift) { result |= RimeModifier.shift }
    if modifiers.contains(.control) { result |= RimeModifier.control }
    if modifiers.contains(.option) { result |= RimeModifier.alt }
    if modifiers.contains(.command) { result |= RimeModifier.superKey }
    return result
  }

  /// 从一次修饰键变化推断出具体是哪个修饰键。
  /// 处理 Caps Lock 长按/短按时需要区分这一点。
  static func inferModifierKeycode(from changes: NSEvent.ModifierFlags) -> UInt16? {
    if changes.contains(.capsLock) { return UInt16(kVK_CapsLock) }
    if changes.contains(.shift) { return UInt16(kVK_Shift) }
    if changes.contains(.control) { return UInt16(kVK_Control) }
    if changes.contains(.option) { return UInt16(kVK_Option) }
    if changes.contains(.command) { return UInt16(kVK_Command) }
    return nil
  }

  static let modifierKeycodes: Set<UInt16> = [
    UInt16(kVK_Shift), UInt16(kVK_RightShift),
    UInt16(kVK_CapsLock),
    UInt16(kVK_Control), UInt16(kVK_RightControl),
    UInt16(kVK_Option), UInt16(kVK_RightOption),
    UInt16(kVK_Command), UInt16(kVK_RightCommand),
    UInt16(kVK_Function),
  ]

  // MARK: - 键码

  static func rimeKeyCode(keycode: UInt16, keychar: Character?,
                          shift: Bool, caps: Bool) -> UInt32 {
    // 先查特例表（修饰键、功能键、方向键等非 ASCII 键）。
    if let code = keycodeMappings[Int(keycode)] {
      return UInt32(code)
    }

    // 再按字符走 ASCII。可打印字符的 X11 键码就是其 ASCII 值。
    if let keychar, keychar.isASCII, let value = keychar.unicodeScalars.first?.value {
      // IBus / Rime 区分大小写字母的键码。
      if keychar.isLowercase, shift != caps {
        return keychar.uppercased().unicodeScalars.first!.value
      }
      switch value {
      case 0x20...0x7e:
        return value
      case 0x1b:
        return UInt32(XK.bracketleft)
      case 0x1c:
        return UInt32(XK.backslash)
      case 0x1d:
        return UInt32(XK.bracketright)
      case 0x1f:
        return UInt32(XK.minus)
      default:
        break
      }
    }

    if let code = additionalCodeMappings[Int(keycode)] {
      return UInt32(code)
    }

    return UInt32(XK.voidSymbol)
  }

  /// 不可打印键。键码取自 X11 `keysymdef.h`，见下方 `XK`。
  private static let keycodeMappings: [Int: Int32] = [
    // 修饰键
    kVK_CapsLock: XK.capsLock,
    kVK_Command: XK.superL,
    kVK_RightCommand: XK.superR,
    kVK_Control: XK.controlL,
    kVK_RightControl: XK.controlR,
    kVK_Function: XK.hyperL,
    kVK_Option: XK.altL,
    kVK_RightOption: XK.altR,
    kVK_Shift: XK.shiftL,
    kVK_RightShift: XK.shiftR,

    // 编辑
    kVK_Delete: XK.backSpace,
    kVK_Escape: XK.escape,
    kVK_ForwardDelete: XK.delete,
    kVK_Help: XK.help,
    kVK_Return: XK.returnKey,
    kVK_Space: XK.space,
    kVK_Tab: XK.tab,

    // 功能键
    kVK_F1: XK.f1, kVK_F2: XK.f2, kVK_F3: XK.f3, kVK_F4: XK.f4,
    kVK_F5: XK.f5, kVK_F6: XK.f6, kVK_F7: XK.f7, kVK_F8: XK.f8,
    kVK_F9: XK.f9, kVK_F10: XK.f10, kVK_F11: XK.f11, kVK_F12: XK.f12,
    kVK_F13: XK.f13, kVK_F14: XK.f14, kVK_F15: XK.f15, kVK_F16: XK.f16,
    kVK_F17: XK.f17, kVK_F18: XK.f18, kVK_F19: XK.f19, kVK_F20: XK.f20,

    // 光标
    kVK_UpArrow: XK.up, kVK_DownArrow: XK.down,
    kVK_LeftArrow: XK.left, kVK_RightArrow: XK.right,
    kVK_PageUp: XK.pageUp, kVK_PageDown: XK.pageDown,
    kVK_Home: XK.home, kVK_End: XK.end,

    // 小键盘
    kVK_ANSI_Keypad0: XK.kp0, kVK_ANSI_Keypad1: XK.kp1,
    kVK_ANSI_Keypad2: XK.kp2, kVK_ANSI_Keypad3: XK.kp3,
    kVK_ANSI_Keypad4: XK.kp4, kVK_ANSI_Keypad5: XK.kp5,
    kVK_ANSI_Keypad6: XK.kp6, kVK_ANSI_Keypad7: XK.kp7,
    kVK_ANSI_Keypad8: XK.kp8, kVK_ANSI_Keypad9: XK.kp9,
    kVK_ANSI_KeypadClear: XK.clear,
    kVK_ANSI_KeypadDecimal: XK.kpDecimal,
    kVK_ANSI_KeypadEquals: XK.kpEqual,
    kVK_ANSI_KeypadMinus: XK.kpSubtract,
    kVK_ANSI_KeypadMultiply: XK.kpMultiply,
    kVK_ANSI_KeypadPlus: XK.kpAdd,
    kVK_ANSI_KeypadDivide: XK.kpDivide,
    kVK_ANSI_KeypadEnter: XK.kpEnter,

    // 其他
    kVK_ISO_Section: XK.section,
    kVK_JIS_Yen: XK.yen,
    kVK_JIS_Underscore: XK.underscore,
    kVK_JIS_KeypadComma: XK.comma,
    kVK_JIS_Eisu: XK.eisuShift,
    kVK_JIS_Kana: XK.kanaShift,
  ]

  /// 有 ASCII 对应，但走特例表更稳的键（数字、标点、字母）。
  ///
  /// 字母与数字的 X11 键码与其 ASCII 值相同，因此字符回退路径本可处理；
  /// 保留此表是为了与参考实现保持一致，且不依赖调用方一定提供了 `keychar`。
  private static let additionalCodeMappings: [Int: Int32] = [
    kVK_ANSI_0: XK.d0, kVK_ANSI_1: XK.d1, kVK_ANSI_2: XK.d2,
    kVK_ANSI_3: XK.d3, kVK_ANSI_4: XK.d4, kVK_ANSI_5: XK.d5,
    kVK_ANSI_6: XK.d6, kVK_ANSI_7: XK.d7, kVK_ANSI_8: XK.d8,
    kVK_ANSI_9: XK.d9,

    kVK_ANSI_RightBracket: XK.bracketright,
    kVK_ANSI_LeftBracket: XK.bracketleft,
    kVK_ANSI_Comma: XK.comma,
    kVK_ANSI_Grave: XK.grave,
    kVK_ANSI_Period: XK.period,
    kVK_ANSI_Semicolon: XK.semicolon,
    kVK_ANSI_Quote: XK.apostrophe,
    kVK_ANSI_Backslash: XK.backslash,
    kVK_ANSI_Minus: XK.minus,
    kVK_ANSI_Slash: XK.slash,
    kVK_ANSI_Equal: XK.equal,

    kVK_ANSI_A: XK.a, kVK_ANSI_B: XK.b, kVK_ANSI_C: XK.c, kVK_ANSI_D: XK.d,
    kVK_ANSI_E: XK.e, kVK_ANSI_F: XK.f, kVK_ANSI_G: XK.g, kVK_ANSI_H: XK.h,
    kVK_ANSI_I: XK.i, kVK_ANSI_J: XK.j, kVK_ANSI_K: XK.k, kVK_ANSI_L: XK.l,
    kVK_ANSI_M: XK.m, kVK_ANSI_N: XK.n, kVK_ANSI_O: XK.o, kVK_ANSI_P: XK.p,
    kVK_ANSI_Q: XK.q, kVK_ANSI_R: XK.r, kVK_ANSI_S: XK.s, kVK_ANSI_T: XK.t,
    kVK_ANSI_U: XK.u, kVK_ANSI_V: XK.v, kVK_ANSI_W: XK.w, kVK_ANSI_X: XK.x,
    kVK_ANSI_Y: XK.y, kVK_ANSI_Z: XK.z,
  ]
}

/// librime 的修饰键掩码。
///
/// 值与 librime `src/rime/key_table.h` 的 `RimeModifier` 一致；
/// 该头文件不在官方预编译包内，因此在此按值复述。
/// `RimeEngine` 的离线用例会验证这些值确实被引擎接受。
enum RimeModifier {
  static let shift: UInt32 = 1 << 0
  static let lock: UInt32 = 1 << 1
  static let control: UInt32 = 1 << 2
  static let alt: UInt32 = 1 << 3
  static let superKey: UInt32 = 1 << 26
}

/// X11 键码常量。
///
/// **为什么不直接 include 头文件**：librime 的 `key_table.h` 依赖
/// `<X11/keysym.h>`，而 macOS 不自带 X11（需装 XQuartz），
/// 官方预编译包也不含 `key_table.h`。
///
/// 因此这里按值复述需要的常量。取值来源是 X11 的 `keysymdef.h`
/// （X Consortium），与 librime 使用的是同一套定义，不是凭记忆写的。
private enum XK {
  static let voidSymbol: Int32 = 0xffffff
  static let space: Int32 = 0x0020

  static let backSpace: Int32 = 0xff08
  static let tab: Int32 = 0xff09
  static let clear: Int32 = 0xff0b
  static let returnKey: Int32 = 0xff0d
  static let escape: Int32 = 0xff1b
  static let delete: Int32 = 0xffff
  static let help: Int32 = 0xff6a
  static let section: Int32 = 0x00a7
  static let yen: Int32 = 0x00a5
  static let underscore: Int32 = 0x005f
  static let comma: Int32 = 0x002c
  static let eisuShift: Int32 = 0xff2f
  static let kanaShift: Int32 = 0xff2e

  static let home: Int32 = 0xff50
  static let left: Int32 = 0xff51
  static let up: Int32 = 0xff52
  static let right: Int32 = 0xff53
  static let down: Int32 = 0xff54
  static let pageUp: Int32 = 0xff55
  static let pageDown: Int32 = 0xff56
  static let end: Int32 = 0xff57

  static let f1: Int32 = 0xffbe
  static let f2: Int32 = 0xffbf
  static let f3: Int32 = 0xffc0
  static let f4: Int32 = 0xffc1
  static let f5: Int32 = 0xffc2
  static let f6: Int32 = 0xffc3
  static let f7: Int32 = 0xffc4
  static let f8: Int32 = 0xffc5
  static let f9: Int32 = 0xffc6
  static let f10: Int32 = 0xffc7
  static let f11: Int32 = 0xffc8
  static let f12: Int32 = 0xffc9
  static let f13: Int32 = 0xffca
  static let f14: Int32 = 0xffcb
  static let f15: Int32 = 0xffcc
  static let f16: Int32 = 0xffcd
  static let f17: Int32 = 0xffce
  static let f18: Int32 = 0xffcf
  static let f19: Int32 = 0xffd0
  static let f20: Int32 = 0xffd1

  static let kp0: Int32 = 0xffb0
  static let kp1: Int32 = 0xffb1
  static let kp2: Int32 = 0xffb2
  static let kp3: Int32 = 0xffb3
  static let kp4: Int32 = 0xffb4
  static let kp5: Int32 = 0xffb5
  static let kp6: Int32 = 0xffb6
  static let kp7: Int32 = 0xffb7
  static let kp8: Int32 = 0xffb8
  static let kp9: Int32 = 0xffb9
  static let kpMultiply: Int32 = 0xffaa
  static let kpAdd: Int32 = 0xffab
  static let kpSubtract: Int32 = 0xffad
  static let kpDecimal: Int32 = 0xffae
  static let kpDivide: Int32 = 0xffaf
  static let kpEnter: Int32 = 0xff8d
  static let kpEqual: Int32 = 0xffbd

  static let shiftL: Int32 = 0xffe1
  static let shiftR: Int32 = 0xffe2
  static let controlL: Int32 = 0xffe3
  static let controlR: Int32 = 0xffe4
  static let capsLock: Int32 = 0xffe5
  static let altL: Int32 = 0xffe9
  static let altR: Int32 = 0xffea
  static let superL: Int32 = 0xffeb
  static let superR: Int32 = 0xffec
  static let hyperL: Int32 = 0xffed

  // 可打印字符：X11 键码即 ASCII 值
  static let a: Int32 = 0x61, b: Int32 = 0x62, c: Int32 = 0x63, d: Int32 = 0x64
  static let e: Int32 = 0x65, f: Int32 = 0x66, g: Int32 = 0x67, h: Int32 = 0x68
  static let i: Int32 = 0x69, j: Int32 = 0x6a, k: Int32 = 0x6b, l: Int32 = 0x6c
  static let m: Int32 = 0x6d, n: Int32 = 0x6e, o: Int32 = 0x6f, p: Int32 = 0x70
  static let q: Int32 = 0x71, r: Int32 = 0x72, s: Int32 = 0x73, t: Int32 = 0x74
  static let u: Int32 = 0x75, v: Int32 = 0x76, w: Int32 = 0x77, x: Int32 = 0x78
  static let y: Int32 = 0x79, z: Int32 = 0x7a

  static let d0: Int32 = 0x30, d1: Int32 = 0x31, d2: Int32 = 0x32, d3: Int32 = 0x33
  static let d4: Int32 = 0x34, d5: Int32 = 0x35, d6: Int32 = 0x36, d7: Int32 = 0x37
  static let d8: Int32 = 0x38, d9: Int32 = 0x39

  static let minus: Int32 = 0x2d
  static let equal: Int32 = 0x3d
  static let bracketleft: Int32 = 0x5b
  static let bracketright: Int32 = 0x5d
  static let backslash: Int32 = 0x5c
  static let semicolon: Int32 = 0x3b
  static let apostrophe: Int32 = 0x27
  static let grave: Int32 = 0x60
  static let slash: Int32 = 0x2f
  static let period: Int32 = 0x2e
}

// ---------------------------------------------------------------------------
// 与参考实现的差异（decisions.md 5.2 要求记录修改）
//
// 1. 类型名 `SquirrelKeycode` → `MacOSKeyCode`；`osxModifiersToRime` →
//    `rimeModifiers(from:)`；`osxKeycodeToRime` → `rimeKeyCode(keycode:keychar:shift:caps:)`。
// 2. 修饰键掩码改为引用本文件内的 `RimeModifier`，不再依赖 librime 头文件
//    （参考实现经 `Sources/Squirrel-Bridging-Header.h` 引入 `rime/key_table.h`，
//    而该头文件不在官方预编译包内，且它依赖 X11 头文件）。
// 3. `XK_*` 常量改为本文件内的 `XK` 枚举，取值按 X11 `keysymdef.h` 复述；
//    参考实现直接使用 X11 宏。
// 4. 键码映射表补入 `kVK_ANSI_KeypadEquals`（参考实现遗漏）与
//    `kVK_JIS_KeypadComma` 的中文注释；映射关系本身未改动。
// 5. 注释改为中文，并补充本项目约定与取值来源说明。
// ---------------------------------------------------------------------------
