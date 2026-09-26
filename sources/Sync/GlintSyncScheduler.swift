// Copyright (C) 2026 EchoJamie <echojamieee@outlook.com>
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit

final class GlintSyncScheduler: NSObject {
  static let shared = GlintSyncScheduler()
  static let changed = Notification.Name("GlintSyncChanged")
  private var timer: Timer?
  private var queued = false
  private(set) var detail = "同步默认关闭。"
  private var sleeping = false
  private override init() {
    super.init()
    let center = NSWorkspace.shared.notificationCenter
    center.addObserver(self, selector: #selector(willSleep), name: NSWorkspace.willSleepNotification, object: nil)
    center.addObserver(self, selector: #selector(didWake), name: NSWorkspace.didWakeNotification, object: nil)
  }
  func configure(startup: Bool = false) {
    timer?.invalidate(); timer = nil
    let prefs = GlintPreferences.shared
    guard prefs.syncEnabled else { detail = "同步已关闭，本机数据保留。"; announce(); return }
    guard !sleeping else { detail = "休眠期间暂停同步。"; announce(); return }
    if prefs.syncIntervalHours > 0 {
      timer = Timer.scheduledTimer(withTimeInterval: prefs.syncIntervalHours * 3600, repeats: true) { [weak self] _ in self?.request() }
      timer?.tolerance = 60
    }
    if startup { request() }
  }
  func request(resolutions: [String: GlintConfigurationSync.Resolution] = [:]) {
    guard GlintPreferences.shared.syncEnabled else { detail = "请先开启同步。"; announce(); return }
    guard !queued, !sleeping else { return }
    queued = true
    detail = "等待输入结束后同步…"; announce()
    let store = GlintDataStore(directory: GlintInputController.runtimeDataURL)
    let root = GlintInputController.dataRootURL
    let family = GlintInputController.runtimeScheme
    let cloud = family == .ice ? GlintSync.defaultCloud : GlintSync.defaultCloud.appendingPathComponent("schemes/" + family.rawValue)
    GlintMaintenance.shared.enqueue("同步词典与配置") {
      // 排队后用户可能关闭同步；关闭立即撤销尚未开始的请求。
      let prefs = GlintPreferences(directory: root)
      prefs.reload()
      guard prefs.syncEnabled else {
        DispatchQueue.main.async { self.queued = false; self.detail = "同步已关闭。"; self.announce() }
        return "同步已取消，本机与云端数据保留。"
      }
      do {
        // 万象命名空间仅在用户已开启同步后创建，不将方案资源放入云端。
        if family != .ice {
          guard FileManager.default.fileExists(atPath: GlintSync.defaultCloud.deletingLastPathComponent().path) else {
            throw GlintError.message("iCloud Drive 目录不可用。")
          }
          try FileManager.default.createDirectory(at: cloud.deletingLastPathComponent(), withIntermediateDirectories: true)
        }
        let message = try GlintSync(store: store, cloud: cloud).synchronize(configuration: prefs.syncConfiguration, resolutions: resolutions)
        DispatchQueue.main.async { self.queued = false; self.detail = message; self.announce() }
        return message
      } catch {
        let message = error.localizedDescription
        GlintLog.write("sync", "request_failed scheme=\(family.rawValue)", error: error)
        DispatchQueue.main.async { self.queued = false; self.detail = message; self.announce() }
        throw error
      }
    }
  }
  private func announce() { NotificationCenter.default.post(name: Self.changed, object: self) }
  @objc private func willSleep() { sleeping = true; timer?.invalidate(); timer = nil }
  @objc private func didWake() { sleeping = false; configure() } // 重新计时，不补跑睡眠期间的次数。
}
