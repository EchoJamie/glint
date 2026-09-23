//
//  GlintInputController.swift
//  Glint
//
//  Copyright (C) 2026 EchoJamie <echojamieee@outlook.com>
//
//  This file is part of Glint, licensed under the GNU General Public License
//  version 3 or later. See LICENSE in the project root.
//

import AppKit
import InputMethodKit

/// 系统输入接入层：把宿主应用的按键交给 Rime，再把引擎的结果送回客户端。
///
/// 职责边界（[功能方案 §6.1](docs/native-candidate-interaction.md#61-保持现有职责)）：
/// 本层只做会话、按键、预编辑与提交的搬运。**不解析拼音、不排序候选、不判断组句**——
/// 那些全是 Rime 的事。选择与学习只能由引擎的 `select_candidate` 触发，
/// 不允许把候选文字直接塞给客户端绕过组句与学习。
///
/// 会话生命周期参考鼠须管 @ `0cd71a61` 的 `sources/SquirrelInputController.swift`，
/// **本文件尚未复用其代码**（见 `docs/decisions.md` 5.2 节）。
///
/// 候选窗口（T0.3）与 Touch Bar（T0.4）尚未接入：现在只有预编辑与提交，
/// 引擎的候选读得到但还没有地方显示。
final class GlintInputController: IMKInputController {
  /// 引擎是进程级共享的，但每个输入会话有自己的 Rime session。
  private static let engine = RimeEngine()

  private var hasSession = false

  /// 引擎只在第一次收到会话时初始化一次，之后各会话共用。
  private static var engineStarted = false

  // MARK: - 会话

  override func activateServer(_ sender: Any!) {
    super.activateServer(sender)
    Self.startEngineIfNeeded()
    Self.engine.openSession()
    hasSession = true
    log("activateServer: \(clientBundleID(sender) ?? "unknown")")
  }

  override func deactivateServer(_ sender: Any!) {
    // 切换应用或输入源时，把未完成的组合收尾，不能留在宿主里。
    // 具体提交什么由引擎决定；这里只负责把它的结果送出去。
    if hasSession {
      Self.engine.clearComposition()
      flush(sender)
      Self.engine.closeSession()
      hasSession = false
    }
    log("deactivateServer: \(clientBundleID(sender) ?? "unknown")")
    super.deactivateServer(sender)
  }

  /// 系统要求结束当前组合（例如点击了别处）。
  override func commitComposition(_ sender: Any!) {
    guard hasSession else { return }
    flush(sender)
    // 纯拼音组合在 Return 时按原样上屏，交由引擎的提交结果决定，
    // 不在这里拼接或猜测文本（功能方案 §4 对 Return 的约定）。
    Self.engine.clearComposition()
    flush(sender)
  }

  // MARK: - 按键

  override func handle(_ event: NSEvent!, client sender: Any!) -> Bool {
    guard hasSession, event.type == .keyDown else { return false }

    // Command 组合键一律不碰，否则会吞掉复制、粘贴、切换输入源等系统快捷键。
    if event.modifierFlags.contains(.command) { return false }

    let keycode = MacOSKeyCode.rimeKeyCode(
      keycode: event.keyCode,
      keychar: event.characters?.first,
      shift: event.modifierFlags.contains(.shift),
      caps: event.modifierFlags.contains(.capsLock)
    )
    guard keycode != 0xffffff else { return false }  // XK_VoidSymbol：认不出的键不拦

    let mask = MacOSKeyCode.rimeModifiers(from: event.modifierFlags)
    guard Self.engine.processKey(Int(keycode), mask: Int(mask)) else {
      // 引擎不要这个键。若当前正在组合中，不能让按键落回宿主造成丢字或误提交，
      // 但这个判断留给 T0.3 按键路由验证时再定，现在先原样交回。
      return false
    }

    flush(sender)
    return true
  }

  override func inputText(_ string: String!, client sender: Any!) -> Bool {
    false
  }

  // MARK: - 与客户端同步

  /// 把引擎的提交结果送出，并刷新预编辑文本。
  ///
  /// 提交**只取一次**：`takeCommit()` 会消费掉引擎的提交，
  /// 重复调用会拿到空值，避免重复上屏（功能方案 §6.4）。
  private func flush(_ sender: Any!) {
    guard let client = sender as? IMKTextInput else { return }

    if let commit = Self.engine.takeCommit(), !commit.isEmpty {
      client.insertText(commit, replacementRange: Self.replacementRange)
    }

    let preedit = Self.engine.preedit ?? ""
    let caret = preedit.utf16.count
    client.setMarkedText(
      preedit,
      selectionRange: NSRange(location: caret, length: 0),
      replacementRange: Self.replacementRange
    )
  }

  /// `NSNotFound` 表示「在客户端当前选区处插入」，即不替代任何已有文本。
  private static let replacementRange = NSRange(location: NSNotFound, length: NSNotFound)

  // MARK: - 引擎初始化

  private static func startEngineIfNeeded() {
    guard !engineStarted else { return }
    engineStarted = true

    let userDir = GlintIds.userDataURL
    try? FileManager.default.createDirectory(at: userDir, withIntermediateDirectories: true)

    // 方案数据目前放在用户数据目录里（与 rime-ice 独立的用法一致）。
    // 随包附带基础数据、首次运行自动部署属于 M1 的范围，见 TASKS.md。
    engine.start(
      appName: "rime.glint",
      userDataDir: userDir.path,
      sharedDataDir: userDir.path,
      logDir: userDir.appendingPathComponent("logs").path
    )
    engine.deploy()
  }

  // MARK: - 诊断

  private func clientBundleID(_ sender: Any!) -> String? {
    guard let client = sender as? IMKTextInput else { return nil }
    return client.bundleIdentifier()
  }

  /// 诊断输出走 stderr。输入法平时由 launchd 拉起，输出没有去处，
  /// 开发时用 `scripts/run-dev.sh` 前台运行并收进日志文件。
  ///
  /// 记录默认只含事件类别，**不含实际输入正文**（`docs/implementation-plan.md` §7）。
  private func log(_ message: String) {
    FileHandle.standardError.write(Data("[glint] \(message)\n".utf8))
  }
}
