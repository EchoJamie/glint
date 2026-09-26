// Copyright (C) 2026 EchoJamie <echojamieee@outlook.com>
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit

/// 设置、部署、词典与同步共用的单队列。仅在组合结束后关闭 session 执行维护。
/// librime 维护发生在后台；维护时保留原始按键传递，并明确显示临时输入状态。
final class GlintMaintenance {
  static let shared = GlintMaintenance()
  static let changed = Notification.Name("GlintMaintenanceChanged")
  enum Phase: String { case idle, waiting, running, applied, failed }
  private(set) var phase: Phase = .idle
  private(set) var detail = "尚未执行维护操作"
  private(set) var operationName = ""
  private(set) var isRunning = false
  private(set) var lastCompletedAt: Date?
  private var pending: [(name: String, operation: () throws -> String, completion: (Bool) -> Void)] = []
  private let queue = DispatchQueue(label: "Glint.maintenance", qos: .userInitiated)
  private var notice: NSPanel?

  func enqueue(_ name: String, completion: @escaping (Bool) -> Void = { _ in }, operation: @escaping () throws -> String) {
    GlintLog.write("maintenance", "queued operation=\(name)")
    pending.append((name, operation, completion))
    drain()
  }

  func drain() {
    guard !isRunning, !pending.isEmpty else { return }
    guard !GlintInputController.hasActiveComposition else {
      if phase != .waiting { GlintLog.write("maintenance", "waiting_for_composition operation=\(pending[0].name)") }
      phase = .waiting; detail = "已排队，等待当前输入结束后\(pending[0].name)"
      announce(); return
    }
    let job = pending.removeFirst()
    let started = ProcessInfo.processInfo.systemUptime
    GlintLog.write("maintenance", "begin operation=\(job.name)")
    operationName = job.name
    phase = .running
    detail = "正在\(job.name)，中文转换暂不可用；按键将原样输入。"
    isRunning = true
    GlintInputController.suspendForMaintenance()
    announce()
    queue.async {
      var result = Result { try job.operation() }
      if case .failure(let error) = result { GlintLog.write("maintenance", "operation_failed operation=\(job.name)", error: error) }
      if !GlintInputController.restartAfterMaintenance() {
        GlintLog.write("maintenance", "engine_resume_failed operation=\(job.name)")
        result = .failure(GlintError.message("维护后引擎未恢复，请查看日志。"))
      }
      DispatchQueue.main.async {
        self.isRunning = false
        switch result {
        case .success(let message):
          self.phase = .applied; self.detail = message; self.lastCompletedAt = Date()
        case .failure(let error):
          self.phase = .failed; self.detail = error.localizedDescription
        }
        self.notice?.orderOut(nil)
        GlintLog.write("maintenance", "end operation=\(job.name) result=\(self.phase.rawValue) elapsed_ms=\(Int((ProcessInfo.processInfo.systemUptime - started) * 1000))")
        GlintInputController.resumeAfterMaintenance()
        job.completion(self.phase == .applied)
        self.announce()
        self.drain()
      }
    }
  }

  private func announce() { NotificationCenter.default.post(name: Self.changed, object: self) }

  func showInputNotice() {
    if notice == nil {
      let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 360, height: 40),
        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
      panel.level = .popUpMenu
      panel.isReleasedWhenClosed = false
      let label = NSTextField(labelWithString: "")
      label.frame = NSRect(x: 12, y: 10, width: 336, height: 20)
      panel.contentView = label
      notice = panel
    }
    (notice?.contentView as? NSTextField)?.stringValue = "正在\(operationName)，按键暂按原文输入"
    if let screen = NSScreen.main {
      notice?.setFrameOrigin(NSPoint(x: screen.visibleFrame.midX - 180, y: screen.visibleFrame.minY + 36))
    }
    notice?.orderFront(nil)
  }
}
