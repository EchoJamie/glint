//
//  Main.swift
//  Glint
//
//  Copyright (C) 2026 EchoJamie <echojamieee@outlook.com>
//
//  This file is part of Glint, licensed under the GNU General Public License
//  version 3 or later. See LICENSE in the project root.
//

import AppKit
import Foundation
import InputMethodKit

/// 进程入口。
///
/// 同一个二进制兼顾两种角色：带参数时执行一次性的安装/查询命令后退出，
/// 不带参数时作为输入法服务常驻。参考 `rime/squirrel` @ `0cd71a61` 的 `sources/Main.swift`。
///
/// 本文件尚未复用参考实现代码（见 `docs/decisions.md` 5.2 节）。
@main
struct GlintApp {
  static func main() {
    if let command = CommandLine.arguments.dropFirst().first {
      switch command {
      case "--install", "--register-input-source":
        InputSourceInstaller.register()
      case "--enable-input-source":
        InputSourceInstaller.enable()
      case "--disable-input-source":
        InputSourceInstaller.disable()
      case "--select-input-source":
        InputSourceInstaller.select()
      case "--list-input-sources":
        InputSourceInstaller.list(filter: CommandLine.arguments.dropFirst(2).first)
      case "--probe-icloud":
        ICloudProbe.run()
      case "--selftest":
        // 可选：Glint --selftest [测试数据目录] [--verbose]
        let rest = Array(CommandLine.arguments.dropFirst(2))
        let verbose = rest.contains("--verbose")
        let dir = rest.first { !$0.hasPrefix("--") }
          ?? (FileManager.default.currentDirectoryPath as NSString)
               .appendingPathComponent("build/testdata")
        exit(SelfTest.run(testDataDir: dir, verbose: verbose))
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

  /// 作为输入法常驻运行。
  ///
  /// Rime 的初始化与部署在 T0.2 接入；此处只建立系统输入会话通道。
  private static func runInputMethodService() {
    let bundle = Bundle.main

    guard let connectionName = bundle.object(forInfoDictionaryKey: "InputMethodConnectionName") as? String,
          let bundleIdentifier = bundle.bundleIdentifier
    else {
      FileHandle.standardError.write(Data("Info.plist 缺少 InputMethodConnectionName 或 CFBundleIdentifier\n".utf8))
      exit(1)
    }

    _ = IMKServer(name: connectionName, bundleIdentifier: bundleIdentifier)

    let app = NSApplication.shared
    // 输入法不占用 Dock 与菜单栏（Info.plist 的 LSUIElement 亦为 true）。
    app.setActivationPolicy(.accessory)
    app.run()
  }

  private static let helpText = """
  Glint —— macOS 中文输入法

  用法：
    Glint                          作为输入法服务常驻运行（由系统拉起，通常不需要手动执行）
    Glint --install                向系统注册输入源
    Glint --enable-input-source    启用输入源
    Glint --disable-input-source   停用输入源
    Glint --select-input-source    切换到本输入源
    Glint --list-input-sources [筛选]
                                   列出系统认识的输入源，排查注册是否生效
    Glint --probe-icloud           iCloud Drive 只读探查（不写入、不读取文件内容）
    Glint --selftest [目录] [--verbose]
                                   候选协议离线用例，需隔离的测试数据（make testdata）
    Glint --help                   显示本说明

  输入源 ID：\(GlintIds.inputSourceID)
  """
}
