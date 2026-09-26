// Copyright (C) 2026 EchoJamie <echojamieee@outlook.com>
// SPDX-License-Identifier: GPL-3.0-or-later
import AppKit
import Carbon
import Foundation

/// 一次性安装器。输入法程序始终以 ZIP 载荷保存，避免挂载盘中的第二份 .app 被登记。
private enum Installation {
  static func run() async throws -> Bool {
    let fm = FileManager.default
    guard let resources = Bundle.main.resourceURL else { throw Failure("安装包缺少资源。") }
    let work = fm.temporaryDirectory.appendingPathComponent("GlintInstall-" + UUID().uuidString)
    try fm.createDirectory(at: work, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: work) }
    try command("/usr/bin/ditto", ["-x", "-k", resources.appendingPathComponent("Glint.app.zip").path, work.path])
    let app = work.appendingPathComponent("Glint.app")
    try command("/usr/bin/codesign", ["--verify", "--strict", app.path])
    if ProcessInfo.processInfo.environment["GLINT_INSTALL_ROOT"] == nil {
      try await stopPreviousVersion()
    }
    try command("/bin/bash", [resources.appendingPathComponent("install-user.sh").path, app.path])
    if ProcessInfo.processInfo.environment["GLINT_INSTALL_ROOT"] == nil {
      let installed = GlintIds.installedAppURL.appendingPathComponent("Contents/MacOS/Glint")
      do { try command(installed.path, ["--install"]) }
      catch { throw Failure("流光已复制完成，但系统未能完成登记。请重试安装；若仍失败，请重新启动 Mac 后再试。") }
      return await needsInputSourceSetup()
    }
    return true
  }

  @MainActor private static func needsInputSourceSetup() -> Bool {
    let filter = [kTISPropertyInputSourceID as String: GlintIds.inputSourceID] as CFDictionary
    let enabled = TISCreateInputSourceList(filter, false)?.takeRetainedValue() as? [TISInputSource] ?? []
    return enabled.isEmpty
  }

  /// 只退出正式安装位置的旧版。正常退出可能被维护任务拒绝，不能强制结束。
  @MainActor private static func stopPreviousVersion() async throws {
    let running = NSRunningApplication.runningApplications(withBundleIdentifier: GlintIds.bundleID)
      .filter { $0.bundleURL?.standardizedFileURL == GlintIds.installedAppURL.standardizedFileURL }
    guard !running.isEmpty else { return }
    if let current = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
       let raw = TISGetInputSourceProperty(current, kTISPropertyBundleID),
       unsafeBitCast(raw, to: CFString.self) as String == GlintIds.bundleID {
      guard let english = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue(),
            TISSelectInputSource(english) == noErr else {
        throw Failure("请从菜单栏的输入法菜单选择 ABC，再点击「重试安装」。")
      }
    }
    let message = "流光暂时无法退出，更新尚未开始。请稍后重试；若仍无法更新，请重新启动 Mac 后再运行安装器。"
    for app in running where !app.isTerminated {
      guard app.terminate() || app.isTerminated else { throw Failure(message) }
    }
    let deadline = ProcessInfo.processInfo.systemUptime + 5
    while running.contains(where: { !$0.isTerminated }) {
      guard ProcessInfo.processInfo.systemUptime < deadline else { throw Failure(message) }
      try await Task.sleep(nanoseconds: 100_000_000)
    }
  }

  private static func command(_ executable: String, _ arguments: [String]) throws {
    let process = Process()
    let output = Pipe()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    process.standardOutput = output
    process.standardError = output
    try process.run()
    let data = output.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
      throw Failure(String(decoding: data.prefix(1500), as: UTF8.self))
    }
  }

  private struct Failure: LocalizedError {
    let reason: String
    init(_ reason: String) { self.reason = reason }
    var errorDescription: String? { reason }
  }
}

@main
private struct GlintInstallerMain {
  private static let delegate = InstallerWindow()
  static func main() {
    let app = NSApplication.shared
    app.setActivationPolicy(.regular)
    app.delegate = delegate
    app.run()
  }
}

private final class InstallerWindow: NSObject, NSApplicationDelegate, NSWindowDelegate {
  private var window: NSWindow?
  private var isInstalling = false
  private let status = NSTextField(labelWithString: "准备安装。")
  private let installButton = NSButton(title: "安装流光", target: nil, action: nil)
  private let settingsButton = NSButton(title: "打开键盘设置", target: nil, action: nil)

  func applicationDidFinishLaunching(_ notification: Notification) {
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 580, height: 330),
      styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
    window.title = "安装流光"
    window.center()
    window.delegate = self
    let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    let title = NSTextField(labelWithString: "流光 \(version)")
    title.font = .boldSystemFont(ofSize: 24)
    title.frame = NSRect(x: 32, y: 260, width: 510, height: 36)
    window.contentView?.addSubview(title)
    let detail = NSTextField(wrappingLabelWithString:
      "安装或更新流光，保留现有词库和设置。请先完成正在输入的文字；更新时会暂时切换为英文，并自动退出旧版流光。")
    detail.frame = NSRect(x: 32, y: 160, width: 510, height: 80)
    window.contentView?.addSubview(detail)
    status.frame = NSRect(x: 32, y: 70, width: 510, height: 76)
    status.lineBreakMode = .byWordWrapping
    status.maximumNumberOfLines = 4
    window.contentView?.addSubview(status)
    installButton.frame = NSRect(x: 415, y: 20, width: 130, height: 32)
    installButton.title = "安装流光 \(version)"
    installButton.target = self
    installButton.action = #selector(install)
    window.contentView?.addSubview(installButton)
    settingsButton.frame = NSRect(x: 255, y: 20, width: 150, height: 32)
    settingsButton.target = self
    settingsButton.action = #selector(openKeyboardSettings)
    settingsButton.isHidden = true
    window.contentView?.addSubview(settingsButton)
    self.window = window
    window.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
  }

  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
  func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    isInstalling ? .terminateCancel : .terminateNow
  }
  func windowShouldClose(_ sender: NSWindow) -> Bool { !isInstalling }

  @objc private func install() {
    guard !isInstalling else { return }
    isInstalling = true
    installButton.isEnabled = false
    status.stringValue = "正在校验并安装…"
    Task { @MainActor in
      do {
        let needsSetup = try await Task.detached(priority: .userInitiated) { try await Installation.run() }.value
        self.isInstalling = false
        self.status.stringValue = needsSetup
          ? "安装完成。点击「打开键盘设置」，在「文本输入」中点「编辑…」，然后添加「流光」。"
          : "安装完成。现在可从菜单栏的输入法菜单选择「流光」，继续输入。"
        self.settingsButton.isHidden = !needsSetup
        self.installButton.title = "完成"
        self.installButton.action = #selector(self.finish)
        self.installButton.isEnabled = true
      } catch {
        self.isInstalling = false
        self.status.stringValue = error.localizedDescription
        self.installButton.title = "重试安装"
        self.installButton.isEnabled = true
      }
    }
  }

  @objc private func finish() { NSApp.terminate(nil) }

  @objc private func openKeyboardSettings() {
    if !NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Library/PreferencePanes/Keyboard.prefPane")) {
      status.stringValue = "请打开「系统设置 → 键盘」，在「文本输入」中点「编辑…」，然后添加「流光」。"
    }
  }
}
