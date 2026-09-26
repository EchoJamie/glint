// Copyright (C) 2026 EchoJamie <echojamieee@outlook.com>
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import InputMethodKit
import IOKit

/// IMK 到宿主候选条的传输边界。本机 macOS 26.6.2 验证；不是公开 SDK 承诺。
/// 不保存候选、不驱动 Rime；候选及高亮始终由输入控制器提供。
enum GlintTouchBar {
  // 只查询当前已注册的硬件一次，不等待设备出现。查不到或查询失败即关闭。
  // 单向关闭项用于隔离验证；不能用它在无硬件的机器上强制开启内部接口。
  static let isAvailable: Bool = {
    guard ProcessInfo.processInfo.environment["GLINT_DISABLE_TOUCH_BAR"] != "1",
          let matching = IOServiceNameMatching("touch-bar") else { return false }
    let device = IOServiceGetMatchingService(kIOMainPortDefault, matching)
    guard device != 0 else { return false }
    IOObjectRelease(device)
    return true
  }()

  static func show(_ candidates: [RimeEngine.Candidate], highlighted: Int?, client: IMKTextInput?) {
    guard isAvailable else { return }
    guard !candidates.isEmpty else { hide(client); return }
    let items = candidates.map { ["text": $0.text] }
    let position = candidates.firstIndex { $0.index == highlighted } ?? 0
    set(11, value: ["candidates": items, "focusedCandidate": items[position], "style": 1] as NSDictionary, client: client)
    set(12, value: NSNumber(value: 1), client: client)
  }

  static func hide(_ client: IMKTextInput?) {
    guard isAvailable else { return }
    // hideAppCandidates 只卸下视图，不清除宿主持有的 candidateList。
    // 先撤回内容，否则上屏/切源后该列表仍可被宿主重新呈现。
    set(11, value: ["candidates": [], "style": 1] as NSDictionary, client: client)
    set(12, value: NSNumber(value: 0), client: client)
  }

  private static func set(_ property: UInt, value: AnyObject, client: IMKTextInput?) {
    guard let receiver = client as? NSObject else { return }
    let selector = NSSelectorFromString("setApplicationProperty:withValue:waitUntilDone:")
    guard receiver.responds(to: selector), let method = receiver.method(for: selector) else { return }
    typealias Setter = @convention(c) (AnyObject, Selector, UInt, AnyObject, Bool) -> Void
    unsafeBitCast(method, to: Setter.self)(receiver, selector, property, value, false)
  }

  /// 系统只回传可见文字。只接受当前候选中的连续可见片段和唯一命中；重名不猜。
  /// 此检查不能证明没有开始回调的旧触摸身份，真实回调边界见接入记录。
  static func index(in candidates: [RimeEngine.Candidate], event: [String: Any]) -> Int? {
    guard let focused = event["focusedCandidate"] as? [String: Any],
          let text = focused["text"] as? String,
          let rows = event["candidates"] as? [[String: Any]] else { return nil }
    let visible = rows.compactMap { $0["text"] as? String }
    guard !visible.isEmpty, visible.count == rows.count, visible.count <= candidates.count,
          visible.contains(text) else { return nil }
    let matches = candidates.filter { $0.text == text }
    guard matches.count == 1,
          (0...(candidates.count - visible.count)).contains(where: { start in
            candidates[start..<(start + visible.count)].map(\.text) == visible
          }) else { return nil }
    return matches[0].index
  }
}
