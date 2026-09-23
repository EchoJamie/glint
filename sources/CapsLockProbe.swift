//
//  CapsLockProbe.swift
//  Glint
//
//  Copyright (C) 2026 EchoJamie <echojamieee@outlook.com>
//
//  This file is part of Glint, licensed under the GNU General Public License
//  version 3 or later. See LICENSE in the project root.
//

import AppKit
import ApplicationServices
import CoreGraphics

/// Caps Lock 长按可行性的实机探针。
///
/// 对应 [decisions.md 3](../docs/decisions.md) 里那条待验证项：
/// Apple 文档通过 `flagsChanged` 检测 Caps Lock 状态，但**现有路径不能直接证明
/// 能够取得完整的物理按下与松开时刻**，因此不能只加一个普通按键计时器就承诺
/// 长按可靠可用。
///
/// 探针要回答的核心问题只有一个：
///
/// > **短按与长按在事件上能否区分？**
///
/// Caps Lock 是翻转键：按下时状态翻转，松开时状态不变。若系统只在状态翻转时
/// 发 `flagsChanged`，那么「快按快放」和「按住一秒再放」看到的事件序列完全相同——
/// 长按就无从测量，除非另开一条能得到物理按下/松开的路径（那需要辅助功能授权）。
///
/// 探针会引导用户各做一次短按与长按，再把两次的事件序列并列出来对比。
/// **它不预设结论**，只负责把证据摆出来。
enum CapsLockProbe {
  /// kVK_CapsLock。`fileprivate` 是为了让同文件的 monitor 也能引用。
  fileprivate static let capsLockKeyCode: UInt16 = 57

  static func run(seconds: TimeInterval) -> Int32 {
    print("Caps Lock 长按可行性探针")
    print("")
    print("访问权限（决定可选路径）：")
    print("  辅助功能（CGEventTap 前提）: \(AXIsProcessTrusted() ? "已授权" : "未授权")")
    print("  输入监控                    : \(CGPreflightListenEventAccess() ? "已授权" : "未授权")")
    let tapWorks = canCreateEventTap()
    print("  全局事件监听                : \(tapWorks ? "可用" : "不可用（需辅助功能授权）")")
    print("")

    print("")
    print("即将弹出一个窗口：**请在该窗口处于前台时按 Caps Lock**。")
    print("按提示先短按一次、再长按一次。")
    print("")

    let monitor = CapsLockMonitor()
    monitor.install()
    // 报告必须在终止进程之前打印——NSApp.terminate 不会回到这里。
    monitor.run(seconds: seconds) {
      print("")
      print("── 结果 ──")
      monitor.report()
    }
    return 0
  }

  private static func canCreateEventTap() -> Bool {
    let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
    let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
                                options: .listenOnly, eventsOfInterest: mask,
                                callback: { _, _, _, _ in nil }, userInfo: nil)
    guard let tap else { return false }
    CFMachPortInvalidate(tap)
    return true
  }
}

/// 收集并展示事件序列。
private final class CapsLockMonitor {
  private struct Sample {
    let at: TimeInterval
    let source: String
    let keyCode: UInt16
    let capsLockOn: Bool
    let flagsRaw: UInt64
  }

  private var samples: [Sample] = []
  private var start = Date()
  private var window: NSWindow?
  private var statusLabel: NSTextField?

  func install() {
    // 本地监听：应用在前台时能收到发给自己的事件。
    NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged, .keyDown]) { [weak self] event in
      self?.record(event, source: "本地")
      return event
    }
    // 全局监听：修饰键变化通常不要求辅助功能授权，但 keyDown 会。
    // 能不能装上本身就是结论的一部分，所以也记下来。
    if NSEvent.addGlobalMonitorForEvents(matching: [.flagsChanged], handler: { [weak self] event in
      self?.record(event, source: "全局")
    }) == nil {
      print("⚠️  全局 flagsChanged 监听未能安装")
    }
  }

  func run(seconds: TimeInterval, onFinish: @escaping () -> Void) {
    let app = NSApplication.shared
    app.setActivationPolicy(.regular)

    let frame = NSRect(x: 0, y: 0, width: 560, height: 200)
    let window = NSWindow(contentRect: frame,
                          styleMask: [.titled, .closable],
                          backing: .buffered, defer: false)
    window.title = "Glint — Caps Lock 探针"
    window.center()

    let label = NSTextField(wrappingLabelWithString: instructions(seconds: seconds))
    label.frame = NSRect(x: 20, y: 20, width: frame.width - 40, height: frame.height - 40)
    label.alignment = .left
    window.contentView?.addSubview(label)

    self.window = window
    self.statusLabel = label
    window.makeKeyAndOrderFront(nil)
    app.activate(ignoringOtherApps: true)

    // 采集通道能不能收到事件，取决于窗口是不是真的拿到了键盘焦点。
    // 先报一次，免得「没收到事件」时无从判断是通道问题还是结论本身。
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
      let active = NSApp.isActive
      let key = window.isKeyWindow
      print("窗口状态：应用前台=\(active ? "是" : "否")  窗口获得焦点=\(key ? "是" : "否")")
      if !key {
        print("⚠️  窗口没有获得键盘焦点，事件不会送进来。请点一下窗口，再重新运行。")
      }
    }

    start = Date()
    Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { _ in
      onFinish()
      NSApp.terminate(nil)
    }
    app.run()
  }

  private func instructions(seconds: TimeInterval) -> String {
    """
    接下来的 \(Int(seconds)) 秒里，请对 Caps Lock 键做两次操作：

      ① 短按一次：快速按下并立即松开（像平时切换大小写那样）
      ② 长按一次：按住约 1 秒再松开

    中间间隔一秒以上，方便区分。

    探针记录事件，不做任何判断，也不会改动你的大小写状态以外的设置。
    """
  }

  private func record(_ event: NSEvent, source: String) {
    // 记录**所有**修饰键变化，不只是 Caps Lock。
    // 这样按一下 Shift 就能确认采集通道是通的——否则用户按了没反应时，
    // 分不清是通道没接上还是结论本就如此。Shift 不留下任何状态，适合做这个对照。
    guard event.type == .flagsChanged else { return }

    let caps = event.modifierFlags.contains(.capsLock)
    let sample = Sample(at: Date().timeIntervalSince(start),
                        source: source,
                        keyCode: event.keyCode,
                        capsLockOn: caps,
                        flagsRaw: UInt64(bitPattern: Int64(event.modifierFlags.rawValue)))
    samples.append(sample)

    let isCaps = event.keyCode == CapsLockProbe.capsLockKeyCode
    print(String(format: "  [%6.3fs] %@ flagsChanged keyCode=%d%@ capsLock=%@ flags=0x%llx",
                 sample.at, source, Int(event.keyCode),
                 isCaps ? "(Caps Lock)" : "", caps ? "开" : "关", sample.flagsRaw))

    // 同时读一次会话级状态：它反映的是**整个会话**的真实锁定状态，
    // 而 NSEvent.modifierFlags 只反映本进程收到的事件流。两者是否一致本身就值得看。
    let session = CGEventSource.flagsState(.combinedSessionState).contains(.maskAlphaShift)
    if session != caps {
      print(String(format: "         └ 会话级状态=%@，与事件流不一致",
                   session ? "开" : "关"))
    }
  }

  /// 把 Caps Lock 状态翻转点提取出来——**翻转点就是按下**。
  /// 若序列里只有翻转点、没有别的，说明松开没有独立事件。
  func report() {
    let flips = samples.filter { $0.keyCode == CapsLockProbe.capsLockKeyCode }
    let others = samples.filter { $0.keyCode != CapsLockProbe.capsLockKeyCode }

    print("修饰键事件共 \(samples.count) 条：Caps Lock \(flips.count) 条，其他 \(others.count) 条")

    guard !flips.isEmpty else {
      print("")
      if others.isEmpty {
        print("❌ **一条修饰键事件都没收到**——这是采集通道的问题，不是 Caps Lock 的结论。")
        print("   可能原因：")
        print("     · 探针窗口没有成为前台窗口（请点一下窗口再按键）")
        print("     · 事件被系统拦截")
        print("   请按一下 Shift 试试：若 Shift 也不出现，就是通道问题，本次结果无效。")
      } else {
        print("⚠️  收到了其他修饰键事件（通道是通的），但**没有 Caps Lock 事件**。")
        print("   这说明 Caps Lock 没有走 flagsChanged 通道，或它的状态未变化。")
      }
      return
    }

    var changes: [(at: TimeInterval, on: Bool)] = []
    var previous: Bool?
    for sample in flips where sample.capsLockOn != previous {
      changes.append((sample.at, sample.capsLockOn))
      previous = sample.capsLockOn
    }

    print("")
    print("状态翻转共 \(changes.count) 次：")
    for change in changes {
      print(String(format: "  %6.3fs  → %@", change.at, change.on ? "开（按下）" : "关（按下）"))
    }

    print("")
    print("── 判定 ──")
    if flips.count == changes.count {
      print("❌ 除状态翻转外没有额外事件。")
      print("   Caps Lock 的**松开不被单独上报**，因此仅凭 flagsChanged")
      print("   **无法测得按住时长**，短按与长按在事件上不可区分。")
      print("   要支持长按，需要另开一条能拿到物理按下/松开的路径。")
    } else {
      let extra = flips.count - changes.count
      print("✅ 除 \(changes.count) 次状态翻转外还有 \(extra) 条事件，可能对应松开。")
      print("   检查上面的时间戳：若某次翻转后有紧随的另一条同 keyCode 事件，")
      print("   两者间隔即为按住时长——长按可测。")
    }

    print("")
    print("说明：本探针走的是 NSEvent 监听，与输入法实际使用的 IMK 路由不是同一条路径。")
    print("      但「松开 Caps Lock 是否产生独立事件」是**系统生成事件**的性质，")
    print("      不取决于投递路径，因此结论可以迁移。")
    print("")
    print("请把上面的完整输出贴回来，据此判断是否值得做长按。")
  }
}
