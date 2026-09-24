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
import Carbon
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

    reportInputPath()
    print("")

    print("")
    print("即将弹出一个窗口。它会先自检采集通道，通过后再提示你按键。")
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

  /// 判断输入是本地键盘还是远程注入。
  ///
  /// **这一点会污染结论，必须先说清楚。** 若按键来自通用控制之类的远程输入，
  /// 那么测出的是**该路径的行为**，不是本地键盘的行为：远程输入可能不转发
  /// Caps Lock 这类本地翻转键，只传最终修饰键状态。
  /// 在拿到本地键盘的数据之前，不能把这个结果当作操作系统的性质。
  ///
  /// 依据：参考实现在处理修饰键时专门写了 `inferModifierKeycode`，
  /// 注释是「Some remote desktop tools send flagsChanged with keyCode 0」——
  /// 说明远程输入的事件形态确实与本地不同。
  private static func reportInputPath() {
    let universalControl = NSRunningApplication
      .runningApplications(withBundleIdentifier: "com.apple.universalcontrol")
      .contains { !$0.isTerminated }

    print("输入路径：")
    print("  通用控制（Universal Control）: \(universalControl ? "运行中" : "未运行")")
    if universalControl {
      print("      （仅当键鼠接在另一台设备上时才影响结论；本机有键盘则无影响）")
    }

    // 当前输入源是本探针**最关键的变量**。
    // 输入法通过 recognizedEvents 声明要接收的事件，IMK 会先路由给它；
    // 输入法返回已处理后，事件就不再送到前台应用。鼠须管就声明了
    // .keyDown | .flagsChanged 并且对多数情况返回 handled=true——
    // 也就是说，**输入法正在时，普通 app 根本看不到 flagsChanged**。
    print("  当前输入源: \(currentInputSourceDescription())")
  }

  /// 当前生效的输入源及其类型。
  private static func currentInputSourceDescription() -> String {
    guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else {
      return "(取不到)"
    }
    func text(_ key: CFString) -> String? {
      guard let raw = TISGetInputSourceProperty(source, key) else { return nil }
      return unsafeBitCast(raw, to: CFString?.self) as String?
    }
    let id = text(kTISPropertyInputSourceID) ?? "?"
    let type = text(kTISPropertyInputSourceType) ?? "?"
    // TIS 的类型串。用字面量比较，避免依赖具体 SDK 版本导出了哪个常量。
    // TISTypeKeyboardLayout 是普通键盘布局；其余（InputMode / InputMethod*）
    // 都意味着有输入法在链路里。
    let isPlainKeyboardLayout = type == "TISTypeKeyboardLayout"
    let verdict = isPlainKeyboardLayout
      ? "普通键盘布局 —— 事件应直达前台应用；看不到就是别的原因"
      : "**有输入法在链路里** —— 它可能已消费 flagsChanged，本探针看不到属预期"
    return "\(id)  类型=\(type)\n      → \(verdict)"
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
    let kind: String
    let keyCode: UInt16
    let capsLockOn: Bool
    let flagsRaw: UInt64

    var isCapsLock: Bool { keyCode == CapsLockProbe.capsLockKeyCode }
    var isKeyboard: Bool { kind == "flagsChanged" || kind == "keyDown" }
  }

  private var samples: [Sample] = []
  private var start = Date()
  private var window: NSWindow?
  private var statusLabel: NSTextField?

  /// 监视器对象**必须持有**：`addLocalMonitorForEvents` 返回的令牌一旦被释放，
  /// 监视器就随之失效。丢掉返回值（用 `_ =` 或 `if ... == nil`）会让它立刻被
  /// ARC 回收——表现为「窗口有焦点但一条事件都收不到」。
  private var monitors: [Any] = []

  func install() {
    // 本地监听：应用在前台时能收到发给自己的事件。
    //
    // 同时监听鼠标——这是**分层实验的关键对照**。鼠标点击不经过输入法，
    // 若鼠标事件能到而键盘事件不能，就精确指向「输入法消费了键盘事件」；
    // 若两者都不到，则是窗口/焦点问题，与输入法无关。
    // 只用点击，不用 mouseMoved——后者每移动一像素就一条，会把输出刷爆。
    let localMask: NSEvent.EventTypeMask = [
      .flagsChanged, .keyDown, .leftMouseDown, .rightMouseDown,
    ]
    if let token = NSEvent.addLocalMonitorForEvents(matching: localMask,
                                                    handler: { [weak self] event in
      self?.record(event, source: "本地")
      return event
    }) {
      monitors.append(token)
    } else {
      print("⚠️  本地监视器未安装")
    }

    // 全局监听：修饰键变化通常不要求辅助功能授权，但 keyDown 会。
    // 能不能装上本身就是结论的一部分。
    if let token = NSEvent.addGlobalMonitorForEvents(matching: [.flagsChanged],
                                                     handler: { [weak self] event in
      self?.record(event, source: "全局")
    }) {
      monitors.append(token)
    } else {
      print("⚠️  全局 flagsChanged 监视器未安装（可能需要辅助功能授权）")
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
    label.frame = NSRect(x: 20, y: 70, width: frame.width - 40, height: frame.height - 90)
    label.alignment = .left
    window.contentView?.addSubview(label)

    // 关键：窗口必须是**文本输入客户端**，修饰键事件才可能被路由进来。
    // 一个没有文本输入上下文的普通窗口可能收不到 flagsChanged——
    // 这也是为什么下面这个输入框不是装饰，而是实验的一部分。
    let field = NSTextField(frame: NSRect(x: 20, y: 20, width: frame.width - 40, height: 34))
    field.placeholderString = "点这里，然后按键（字母应出现在此框中）"
    window.contentView?.addSubview(field)
    window.makeFirstResponder(field)

    self.window = window
    self.statusLabel = label
    window.makeKeyAndOrderFront(nil)
    app.activate(ignoringOtherApps: true)

    // 先用合成事件自检采集通道，通过了再让用户按键。
    // 否则「没收到事件」时无法区分是通道坏了还是结论本就如此，
    // 白白浪费一次人工操作。自检不需要任何系统权限。
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
      let active = NSApp.isActive
      let key = window.isKeyWindow
      print("窗口状态：应用前台=\(active ? "是" : "否")  窗口获得焦点=\(key ? "是" : "否")")
      // NSApp.isActive 只是本进程的看法。真实的事件路由由系统决定，
      // 所以直接问系统「此刻谁在最前」——两者不一致正是本机现象的原因。
      print("系统认定的前台应用：\(Self.frontmostApplicationName())")

      self.verifyChannel(window: window) { healthy in
        self.samples.removeAll()
        self.start = Date()
        if healthy {
          print("")
          print("── 现在请按键 ──")
          print("① 短按一次 Caps Lock（快按快放）")
          print("② 隔一秒，长按一次（按住约 1 秒再松开）")
          print("")
        } else {
          print("")
          print("自检未通过，继续按键没有意义——请把以上输出贴回来。")
        }
        Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { _ in
          onFinish()
          NSApp.terminate(nil)
        }
      }
    }

    app.run()
  }

  /// 系统认定的前台应用。与本进程的 `NSApp.isActive` 对照，
  /// 用来判断事件实际会被路由到哪里。
  static func frontmostApplicationName() -> String {
    NSWorkspace.shared.frontmostApplication?.localizedName ?? "(未知)"
  }

  /// 往自己的事件队列投一个合成事件，确认监视器能收到。
  ///
  /// 这是唯一能在无人按键、无系统权限的情况下验证采集通道的办法：
  /// `NSApp.postEvent` 是进程内 API，不经过系统权限。
  private func verifyChannel(window: NSWindow, completion: @escaping (Bool) -> Void) {
    // 56 = kVK_Shift。用 Shift 而不是 Caps Lock：合成事件不会真的翻转锁定状态。
    guard let event = NSEvent.keyEvent(
      with: .flagsChanged,
      location: .zero,
      modifierFlags: [.shift],
      timestamp: ProcessInfo.processInfo.systemUptime,
      windowNumber: window.windowNumber,
      context: nil,
      characters: "",
      charactersIgnoringModifiers: "",
      isARepeat: false,
      keyCode: 56
    ) else {
      print("自检：无法构造合成事件，跳过")
      completion(false)
      return
    }

    let before = samples.count
    NSApp.postEvent(event, atStart: false)
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
      let received = self.samples.count > before
      print(received
            ? "自检：✅ 监视器收到了合成事件，采集通道正常"
            : "自检：❌ 连合成事件都收不到，监视器本身有问题（不是 Caps Lock 的结论）")
      completion(received)
    }
  }

  private func instructions(seconds: TimeInterval) -> String {
    """
    请依次做四件事，每步之间隔一秒以上：

      ① 在窗口内点一下鼠标      ← 最底层对照：应用到底有没有在收事件
      ② 敲一个普通字母，比如 a  ← 键盘事件有没有到达应用
      ③ 短按一次 Caps Lock
      ④ 长按一次 Caps Lock（按住约 1 秒再松开）

    窗口标题栏实时显示已收到的事件数，变了说明事件到了，不必等结束。

    某一步「前一层到了、后一层没到」，问题就精确落在那一层，不用猜。

    探针只记录事件，不改动任何设置。
    """
  }

  private func record(_ event: NSEvent, source: String) {
    // 记录修饰键、普通按键与鼠标。三者构成分层对照：
    //   鼠标到了 → 应用确实在收事件
    //   字母到了 → 键盘事件能到达应用
    //   Caps Lock 到了 → 才能回答长按能否测得
    // 缺哪一层，问题就定位在哪一层，不必猜。
    guard event.type == .flagsChanged || event.type == .keyDown
       || event.type == .leftMouseDown || event.type == .rightMouseDown else { return }

    let caps = event.modifierFlags.contains(.capsLock)
    let kind: String
    switch event.type {
    case .flagsChanged: kind = "flagsChanged"
    case .keyDown: kind = "keyDown"
    case .leftMouseDown: kind = "鼠标左键"
    case .rightMouseDown: kind = "鼠标右键"
    default: return
    }

    let sample = Sample(at: Date().timeIntervalSince(start),
                        source: source,
                        kind: kind,
                        keyCode: event.keyCode,
                        capsLockOn: caps,
                        flagsRaw: UInt64(bitPattern: Int64(event.modifierFlags.rawValue)))
    samples.append(sample)
    // 标题栏实时显示计数：用户按键时能立刻看到事件到没到，
    // 不必等到 20 秒结束才知道白按了。
    window?.title = "Glint — Caps Lock 探针（已收到 \(samples.count) 条事件）"

    let detail = sample.isKeyboard
      ? String(format: " keyCode=%d%@ capsLock=%@ flags=0x%llx",
               Int(event.keyCode), sample.isCapsLock ? "(Caps Lock)" : "",
               caps ? "开" : "关", sample.flagsRaw)
      : ""
    print(String(format: "  [%6.3fs] %@ %-12@%@", sample.at, source, kind as NSString, detail))

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
    // 分层统计：鼠标 / 键盘 / Caps Lock。
    // 从下往上逐层排除，缺哪一层问题就在哪一层，不必猜。
    let mouse = samples.filter { !$0.isKeyboard }
    let keyboard = samples.filter(\.isKeyboard)
    let flips = samples.filter(\.isCapsLock)

    print("收到事件共 \(samples.count) 条")
    print("  鼠标:      \(mouse.count) 条")
    print("  键盘:      \(keyboard.count) 条（其中 Caps Lock \(flips.count) 条）")
    print("报告时系统认定的前台应用：\(Self.frontmostApplicationName())")
    print("")

    guard !flips.isEmpty else {
      print("── 判定 ──")
      if mouse.isEmpty && keyboard.isEmpty {
        print("❌ 连**鼠标点击**都没收到——应用根本没在接收事件，与 Caps Lock 无关。")
        print("   自检能收到 in-process 事件，说明监视器本身没问题。")
        print("   请确认按键时探针窗口确实在前台（点一下窗口再操作）。")
      } else if keyboard.isEmpty {
        print("❌ 鼠标事件到了，**键盘事件一条都没有**。")
        print("   这说明键盘事件在到达本应用之前就被截走了。")
        print("   最可能是当前输入法消费了它们——见上方「当前输入源」一行。")
        print("   这条结论本身有价值：**输入法在位时，普通应用看不到键盘事件；")
        print("   而输入法自己能看到** —— Glint 将来正是输入法，这一点对我们有利。")
      } else {
        print("⚠️  键盘事件到了，但没有 Caps Lock 事件。")
        print("   这是真结论：Caps Lock 没有以 flagsChanged 形式送达，或状态未变化。")
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
