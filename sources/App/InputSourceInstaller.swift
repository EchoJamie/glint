// Copyright (C) 2026 EchoJamie <echojamieee@outlook.com>
// SPDX-License-Identifier: GPL-3.0-or-later

import Carbon
import Foundation

/// 输入源的注册、启用、切换。
///
/// 参考 `rime/squirrel` @ `0cd71a61` 的 `sources/InputSource.swift`。
/// 与参考实现的主要差别是只处理简体一个输入模式，且不使用硬编码的安装路径。
enum InputSourceInstaller {
  /// 本产品的输入源，**两项，缺一不可**：
  ///
  /// - **父项**（bundle ID）：带 mode 的输入法，父项自身不可选（`IsSelectCapable`
  ///   恒为 false），但**必须处于启用状态**。
  /// - **模式项**（`.Hans`）：真正可被切换的那一项。
  ///
  /// TIS 的规则是「mode 只有在**它与父项都启用**时才可选」——
  /// 父项未启用时 `TISSelectInputSource` 直接返回 `paramErr (-50)`。
  private static var sourceIDs: [String] { [GlintIds.bundleID, GlintIds.inputSourceID] }

  /// 系统当前已加载的全部输入源。
  private static var allSources: [TISInputSource] {
    TISCreateInputSourceList(nil, true)?.takeRetainedValue() as? [TISInputSource] ?? []
  }

  /// 该输入源是否确实指向**本 app 的安装副本**。
  ///
  /// 图标属性按 SDK 声明读取为 CFURLRef；比较解码后的完整安装路径。
  /// 父项没有图标 URL，返回 false，因此不会把父项误判成「有据可依」。
  private static func backedByInstalledApp(_ source: TISInputSource) -> Bool {
    guard let url = urlProperty(of: source, kTISPropertyIconImageURL), url.isFileURL else { return false }
    return url.standardizedFileURL.path.hasPrefix(GlintIds.installedAppURL.standardizedFileURL.path + "/")
  }

  /// 系统当前已加载的输入源，按 ID 索引。
  ///
  /// **同一个 ID 可能出现多条记录**——旧名单（`com.apple.HIToolbox`）与
  /// 第三方名单（`com.apple.inputsources`）各写一处时就会这样。
  /// 这里优先保留**确实指向安装副本**的那一条：否则 enable / select 可能
  /// 作用在一个空壳上。实测症状正是「菜单点击无效，而按 ID 查找的程序化
  /// 切换有效」——两者命中的是不同的那一条。见 docs/troubleshooting.md。
  private static var loadedSources: [String: TISInputSource] {
    var result = [String: TISInputSource]()
    for source in allSources {
      guard let id = stringProperty(of: source, kTISPropertyInputSourceID) else { continue }
      if let existing = result[id], backedByInstalledApp(existing) || !backedByInstalledApp(source) {
        continue   // 已有的一条更可信，或新的这条并不更可信 → 保留已有的
      }
      result[id] = source
    }
    return result
  }

  /// 各 ID 在 TIS 里出现了几次。多于一次即为重复记录。
  private static var duplicateIDCounts: [String: Int] {
    var counts: [String: Int] = [:]
    for source in allSources {
      guard let id = stringProperty(of: source, kTISPropertyInputSourceID) else { continue }
      counts[id, default: 0] += 1
    }
    return counts.filter { $0.value > 1 }
  }

  /// 本输入法是否已由**系统设置**登记进第三方输入法名单。
  ///
  /// 这份名单（`com.apple.inputsources` → `AppleEnabledThirdPartyInputSources`）
  /// 才是第三方输入法的正规出处。判据取自我方实测：鼠须管在本机
  /// **只有这份名单里有记录，旧名单里没有**。
  private static var isInThirdPartyList: Bool {
    let defaults = UserDefaults(suiteName: "com.apple.inputsources")
    let list = defaults?.array(forKey: "AppleEnabledThirdPartyInputSources") as? [[String: Any]] ?? []
    return list.contains { ($0["Bundle ID"] as? String) == GlintIds.bundleID }
  }

  /// 系统里已经登记的本输入源实例。
  ///
  /// 判据同时看两个属性：`InputSourceID` 与 `InputModeID`——父项与模式项各用其一，
  /// 只看一个会漏（参考实现 vChewing 的 `match(identifiers:modeIDs:)` 也是两者都看）。
  private static var registeredInstances: [TISInputSource] {
    let wanted = Set(sourceIDs)
    guard let list = TISCreateInputSourceList(nil, true)?.takeRetainedValue() as? [TISInputSource] else {
      return []
    }
    return list.filter { source in
      let id = stringProperty(of: source, kTISPropertyInputSourceID)
      let mode = stringProperty(of: source, kTISPropertyInputModeID)
      return (id.map(wanted.contains) ?? false) || (mode.map(wanted.contains) ?? false)
    }
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
      report("   系统会为它建一条 LaunchServices 记录，使同一个 bundle ID 出现两个路径；")
      report("   请改用安装副本（make install 之后）。")
    }
    // TISRegisterInputSource 是追加语义；已有实例时不能再注册。
    let existing = registeredInstances
    if !existing.isEmpty {
      report("输入源已注册（系统中有 \(existing.count) 份记录），跳过注册这一步。")
      reportNextStep()
      return
    }

    // 返回值必须看：注册失败时系统不报错也不提示，只体现在这个 OSStatus 上。
    let status = TISRegisterInputSource(appURL as CFURL)
    if status == noErr {
      report("已从 \(appURL.path) 注册输入源。")
      report("注册返回成功仍需核对系统输入源列表和实际输入；排查入口：scripts/diagnose-registration.sh。")
      reportNextStep()
    } else {
      report("注册失败，OSStatus = \(status)")
      report("   常见原因：签名无效、打包不完整、bundle 不在标准输入法目录下。")
      exit(1)
    }
  }

  /// 注册之后该做什么——**不是**用本程序启用。
  ///
  /// TISEnableInputSource 写旧 HIToolbox 名单；第三方输入法应由系统设置
  /// 写入 com.apple.inputsources。两处同时登记会造成重复条目。
  private static func reportNextStep() {
    if isInThirdPartyList {
      report("输入源已在系统名单中，无需再启用。")
    } else {
      report("下一步：**在系统设置里添加**，不要用本程序启用——")
      report("   系统设置 → 键盘 → 文本输入 → 输入法 → 编辑 → + → Chinese, Simplified → 流光")
      report("   那条路径才会正确写进第三方名单（模式项与父项各一条）。")
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
    let id = GlintIds.inputSourceID
    guard let source = loadedSources[id] else {
      report("找不到输入源 \(id)。先执行 Glint --install。")
      return
    }
    guard boolProperty(of: source, kTISPropertyInputSourceIsEnabled) == true,
          boolProperty(of: source, kTISPropertyInputSourceIsSelectCapable) == true
    else {
      report("输入源未启用或不可选：\(id)")
      return
    }
    let status = TISSelectInputSource(source)
    report(status == noErr
      ? "系统已选中：\(id)；当前文本客户端是否激活输入法仍需验证"
      : "切换失败（\(status)）：\(id)")
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

      // **显示名一定要打印**：它等于 ID 原文时，说明 bundle 的 InfoPlist.strings
      // 里没为这个输入源 ID 定义名字（`CFBundleName` 管不到输入源）。
      // 这种情况下 TIS 看着一切正常，但系统设置与输入法菜单里根本列不出来——
      // 见 docs/troubleshooting.md。
      let name = stringProperty(of: source, kTISPropertyLocalizedName) ?? "-"
      let nameNote = (name == id) ? "   ⚠️ 显示名退回了 ID —— 缺 InfoPlist.strings 条目" : ""

      print("  \(id)")
      print("      名称 \(name)\(nameNote)")
      print("      类型 \(kind)  \(enabled)  \(selectable)  bundle=\(bundle)")
    }

    // **重复记录要主动点出来。** 同一个 ID 出现两遍时，界面症状是
    // 「菜单项点了没反应」「设置里有多行同名条目」，而每一处数据单看都正常，
    // 极难查——实测为此花了很久。这里直接把判据与修法打出来。
    if let (id, count) = duplicateIDCounts
        .filter({ filter == nil || $0.key.localizedCaseInsensitiveContains(filter!) })
        .sorted(by: { $0.value > $1.value }).first {
      report("")
      report("⚠️  \(id) 在系统里有 \(count) 份记录（应只有 1 份）。")
      report("   先核对安装副本和系统设置中的输入源；参见 docs/troubleshooting.md。")
      report("   如需重加，请通过系统设置移除后添加流光。")
    }

    if let filter, matched == 0 {
      report("没有匹配「\(filter)」的输入源。")
      report("请核对安装路径、程序签名、产品标识及本地化名称，再检查系统设置中的输入源。")
      report("只读排查入口：scripts/diagnose-registration.sh；参见 docs/troubleshooting.md。")
    } else if filter == nil {
      report("（未筛选，以上为全部）")
    }
  }

  // MARK: - 属性读取

  private static func stringProperty(of source: TISInputSource, _ key: CFString) -> String? {
    guard let raw = TISGetInputSourceProperty(source, key) else { return nil }
    return unsafeBitCast(raw, to: CFString?.self) as String?
  }

  private static func urlProperty(of source: TISInputSource, _ key: CFString) -> URL? {
    guard let raw = TISGetInputSourceProperty(source, key) else { return nil }
    return unsafeBitCast(raw, to: CFURL.self) as URL
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
