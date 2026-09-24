//
//  InputSourceInstaller.swift
//  Glint
//
//  Copyright (C) 2026 EchoJamie <echojamieee@outlook.com>
//
//  This file is part of Glint, licensed under the GNU General Public License
//  version 3 or later. See LICENSE in the project root.
//

import Carbon
import Foundation

/// 输入源的注册、启用、切换。
///
/// 参考 `rime/squirrel` @ `0cd71a61` 的 `sources/InputSource.swift`。
/// 本文件尚未复用参考实现代码（见 `docs/decisions.md` 5.2 节）；
/// 与参考实现的主要差别是只处理简体一个输入模式，且不使用硬编码的安装路径。
enum InputSourceInstaller {
  /// 本产品的输入源。只做简体，因此只有一项。
  private static var sourceIDs: [String] { [GlintIds.inputSourceID] }

  /// 系统当前已加载的输入源，按 ID 索引。
  private static var loadedSources: [String: TISInputSource] {
    var result = [String: TISInputSource]()
    guard let list = TISCreateInputSourceList(nil, true)?.takeRetainedValue() as? [TISInputSource] else {
      return result
    }
    for source in list {
      guard let id = stringProperty(of: source, kTISPropertyInputSourceID) else { continue }
      result[id] = source
    }
    return result
  }

  /// 向系统注册本输入源。
  ///
  /// 前提是 `Glint.app` 已经位于 `~/Library/Input Methods/`——系统只认安装目录下的副本，
  /// 直接注册构建产物不会生效。安装与构建因此是分开的两步（`make install`）。
  static func register() {
    // 注册**自己所在的 bundle**，而不是写死的安装路径。
    //
    // 之前这里用的是 GlintIds.installedAppURL（硬编码 ~/Library/Input Methods/），
    // 于是从系统级副本运行时注册的仍是用户级那份——测试因此无效，
    // 而且真实的安装位置永远无法生效。
    let appURL = Bundle.main.bundleURL
    guard appURL.pathExtension == "app" else {
      report("当前可执行文件不在 .app 包内（\(appURL.path)），无法注册。")
      report("   请从已安装的副本运行，例如 make install 之后。")
      exit(1)
    }
    if appURL.path.contains("/build/") {
      report("⚠️  正在注册构建目录中的产物：\(appURL.path)")
      report("   系统通常不会接受构建目录里的输入法，请先安装。")
    }
    // 返回值必须看：注册失败时系统不报错也不提示，只体现在这个 OSStatus 上。
    let status = TISRegisterInputSource(appURL as CFURL)
    if status == noErr {
      report("已从 \(appURL.path) 注册输入源。")
      report("若输入源菜单中尚未出现，请注销并重新登录。")
    } else {
      report("注册失败，OSStatus = \(status)")
      report("   常见原因：签名无效、打包不完整、bundle 不在标准输入法目录下。")
      exit(1)
    }
  }

  static func enable() {
    for id in sourceIDs {
      guard let source = loadedSources[id] else {
        report("找不到输入源 \(id)。先执行 Glint --install。")
        continue
      }
      if boolProperty(of: source, kTISPropertyInputSourceIsEnabled) == true {
        report("输入源已启用：\(id)")
        continue
      }
      let status = TISEnableInputSource(source)
      report(status == noErr ? "已启用：\(id)" : "启用失败（\(status)）：\(id)")
    }
  }

  static func disable() {
    for id in sourceIDs {
      guard let source = loadedSources[id] else { continue }
      guard boolProperty(of: source, kTISPropertyInputSourceIsEnabled) == true else { continue }
      let status = TISDisableInputSource(source)
      report(status == noErr ? "已停用：\(id)" : "停用失败（\(status)）：\(id)")
    }
  }

  static func select() {
    for id in sourceIDs {
      guard let source = loadedSources[id] else {
        report("找不到输入源 \(id)。先执行 Glint --install。")
        continue
      }
      guard boolProperty(of: source, kTISPropertyInputSourceIsEnabled) == true,
            boolProperty(of: source, kTISPropertyInputSourceIsSelectCapable) == true
      else {
        report("输入源未启用或不可选：\(id)")
        continue
      }
      let status = TISSelectInputSource(source)
      report(status == noErr ? "已切换到：\(id)" : "切换失败（\(status)）：\(id)")
    }
  }

  /// 列出系统当前认识的全部输入源。
  ///
  /// 存在的理由：注册与启用是**两个进程**（每次调用一个子命令），注册是否已经
  /// 对系统生效无法凭返回值判断。这个方法把 TIS 实际看到的东西打出来，
  /// 用来区分「没注册上」「注册了但没启用」「有多个同名残留」。
  ///
  /// `includeAllInstalled` 传 true，因此包含已安装但未启用的输入源。
  static func list(filter: String?) {
    guard let sources = TISCreateInputSourceList(nil, true)?.takeRetainedValue() as? [TISInputSource] else {
      report("TISCreateInputSourceList 返回空，无法列出输入源。")
      return
    }

    var matched = 0
    report("TIS 可见的输入源共 \(sources.count) 个" + (filter.map { "，筛选「\($0)」" } ?? ""))

    for source in sources {
      let id = stringProperty(of: source, kTISPropertyInputSourceID) ?? "(无 ID)"
      if let filter, !id.localizedCaseInsensitiveContains(filter) { continue }
      matched += 1

      let kind = stringProperty(of: source, kTISPropertyInputSourceType) ?? "?"
      let enabled = boolProperty(of: source, kTISPropertyInputSourceIsEnabled).map { $0 ? "已启用" : "未启用" } ?? "?"
      let selectable = boolProperty(of: source, kTISPropertyInputSourceIsSelectCapable).map { $0 ? "可选" : "不可选" } ?? "?"
      let bundle = stringProperty(of: source, kTISPropertyBundleID) ?? "-"

      print("  \(id)")
      print("      类型 \(kind)  \(enabled)  \(selectable)  bundle=\(bundle)")
    }

    if let filter, matched == 0 {
      report("没有匹配「\(filter)」的输入源。")
      report("注册未生效的常见原因：")
      report("  1. 签名无效时系统会静默拒绝（先跑 codesign --verify --strict）")
      report("  2. 应用不在系统认可的输入法目录下：/Library/Input Methods/ 或 ~/Library/Input Methods/")
      report("  3. 部分安装位置需要注销并重新登录后系统才扫描到")
    } else if filter == nil {
      report("（未筛选，以上为全部）")
    }
  }

  // MARK: - 属性读取

  private static func stringProperty(of source: TISInputSource, _ key: CFString) -> String? {
    guard let raw = TISGetInputSourceProperty(source, key) else { return nil }
    return unsafeBitCast(raw, to: CFString?.self) as String?
  }

  private static func boolProperty(of source: TISInputSource, _ key: CFString) -> Bool? {
    guard let raw = TISGetInputSourceProperty(source, key) else { return nil }
    guard let value = unsafeBitCast(raw, to: CFBoolean?.self) else { return nil }
    return CFBooleanGetValue(value)
  }

  private static func report(_ message: String) {
    print("[glint] \(message)")
  }
}
