// Copyright (C) 2026 EchoJamie <echojamieee@outlook.com>
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import Foundation
import InputMethodKit

/// 进程入口。
///
/// 同一个二进制兼顾两种角色：带参数时执行一次性的安装/查询命令后退出，
/// 不带参数时作为输入法服务常驻。参考 `rime/squirrel` @ `0cd71a61` 的 `sources/Main.swift`。
///
@main
struct GlintApp {
  static func main() {
    // LaunchServices 的 -psn / -LaunchArguments 等参数不是我们的 CLI 命令。
    // 若误判后退出，系统会回退输入源；排查判据见 docs/troubleshooting.md。
    let args = Array(CommandLine.arguments.dropFirst())
    if let command = args.first, command.hasPrefix("--") || command == "-h" {
      switch command {
      case "--install", "--register-input-source":
        InputSourceInstaller.register()
      case "--disable-input-source":
        InputSourceInstaller.disable()
      case "--select-input-source":
        InputSourceInstaller.select()
      case "--list-input-sources":
        InputSourceInstaller.list(filter: CommandLine.arguments.dropFirst(2).first)
      case "--settings":
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: GlintIds.bundleID)
          .contains { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier && $0.bundleURL == Bundle.main.bundleURL }
        if running {
          DistributedNotificationCenter.default().postNotificationName(GlintApplicationDelegate.openSettings,
            object: Bundle.main.bundlePath, userInfo: nil, deliverImmediately: true)
        } else { runInputMethodService(showSettings: true) }
      case "--prepare-user-dictionary":
        guard args.count == 3 else { print("需要源 .userdb 路径与尚不存在的输出目录。"); exit(2) }
        do {
          let output = try GlintMigration.prepareSnapshot(database: URL(fileURLWithPath: args[1]), destination: URL(fileURLWithPath: args[2]))
          let snapshot = try DictionaryText(data: Data(contentsOf: output), kind: .snapshot)
          print("已生成 \(snapshot.entries) 条学习记录的原生快照：\(output.path)。原词库未改动。")
        } catch { print(error.localizedDescription); exit(1) }
      case "--help", "-h":
        print(helpText)
      default:
        FileHandle.standardError.write(Data("未知参数：\(command)\n\n\(helpText)\n".utf8))
        exit(2)
      }
      return
    }

    runInputMethodService()
  }

  /// 必须持有 IMKServer，否则 ARC 回收后进程仍活着却不能提供输入服务。
  private static var server: IMKServer?
  private static var appDelegate: GlintApplicationDelegate?

  /// 作为输入法常驻运行。
  ///
  /// 建立系统输入会话通道；Rime 由控制器初始化，设置复用同一进程。
  private static func runInputMethodService(showSettings: Bool = false) {
    let bundle = Bundle.main
    GlintLog.current = GlintLog(directory: GlintIds.userDataURL.appendingPathComponent("logs"))
    GlintLog.write("service", "start version=\(bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") ?? "unknown") build=\(bundle.object(forInfoDictionaryKey: "CFBundleVersion") ?? "unknown") os=\(ProcessInfo.processInfo.operatingSystemVersionString) touchBar=\(GlintTouchBar.isAvailable)")

    guard let connectionName = bundle.object(forInfoDictionaryKey: "InputMethodConnectionName") as? String,
          let bundleIdentifier = bundle.bundleIdentifier
    else {
      GlintLog.write("service", "invalid_bundle missing_connection_or_identifier")
      FileHandle.standardError.write(Data("Info.plist 缺少 InputMethodConnectionName 或 CFBundleIdentifier\n".utf8))
      exit(1)
    }

    // 创建失败必须大声失败：**静默地跑一个不提供任何服务的进程**，
    // 表现为「输入法切过去又跳回来」，极难查（本项目为此排查过很久）。
    guard let created = IMKServer(name: connectionName, bundleIdentifier: bundleIdentifier) else {
      GlintLog.write("service", "imk_server_creation_failed")
      FileHandle.standardError.write(Data("""
        ❌ IMKServer 创建失败：connectionName=\(connectionName) bundleID=\(bundleIdentifier)
           输入法将无法提供服务。请核对 Info.plist 的 InputMethodConnectionName
           与 InputMethodServerControllerClass。
        \n
        """.utf8))
      exit(1)
    }
    server = created
    GlintLog.write("service", "imk_server_ready")

    let app = NSApplication.shared
    // 输入法不占用 Dock 与菜单栏（Info.plist 的 LSUIElement 亦为 true）。
    app.setActivationPolicy(.accessory)
    let delegate = GlintApplicationDelegate()
    appDelegate = delegate; app.delegate = delegate
    if showSettings { delegate.presentSettings() }
    app.run()
  }

  private static let helpText = """
  Glint —— macOS 中文输入法

  用法：
    Glint                          作为输入法服务常驻运行（由系统拉起，通常不需要手动执行）
    Glint --install                向系统注册输入源（**只注册，不启用**）
    Glint --disable-input-source   停用输入源
    Glint --select-input-source    请求系统选中本输入源（不验证客户端激活）
    Glint --list-input-sources [筛选]
                                   列出系统认识的输入源；会主动点出重复记录
    Glint --settings               打开当前输入法进程的设置窗口
    Glint --prepare-user-dictionary <源.userdb> <新目录>
                                   从已关闭的词库副本生成快照，不修改原目录
    Glint --help                   显示本说明

  输入源 ID：\(GlintIds.inputSourceID)
  """
}

final class GlintApplicationDelegate: NSObject, NSApplicationDelegate {
  static let openSettings = Notification.Name("com.github.echojamie.inputmethod.Glint.openSettings")
  override init() {
    super.init()
    DistributedNotificationCenter.default().addObserver(self, selector: #selector(presentSettings),
      name: Self.openSettings, object: Bundle.main.bundlePath)
  }
  @objc func presentSettings() {
    guard GlintInputController.startEngineIfNeeded() else { return }
    GlintSettingsWindow.shared.present()
  }
  func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
    presentSettings(); return true
  }
  func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    let maintenance = GlintMaintenance.shared
    return maintenance.isRunning || maintenance.phase == .waiting ? .terminateCancel : .terminateNow
  }
  func applicationWillTerminate(_ notification: Notification) {
    GlintInputController.stopEngine()
  }
}
