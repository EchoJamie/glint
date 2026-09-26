// Copyright (C) 2026 EchoJamie <echojamieee@outlook.com>
// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import CryptoKit

enum GlintInputScheme: String, CaseIterable, Codable {
  case ice = "rime_ice", wanxiang
  var name: String { self == .ice ? "雾凇拼音" : "万象拼音" }
  var version: String { self == .ice ? "内置" : "Base 18.0.11" }
  var source: URL { URL(string: self == .ice ? "https://github.com/iDvel/rime-ice" : "https://github.com/amzxyz/rime-wanxiang")! }
  func directory(in root: URL) -> URL {
    // 保留原日用雾凇的位置与全部学习记录，新增方案单独存储。
    self == .ice ? root : root.appendingPathComponent("schemes/" + rawValue)
  }
  enum Layout: String, CaseIterable, Codable {
    case full, flypy, zrm, mspy, sogou, abc, ziguang, jiajia
    var name: String {
      switch self {
      case .full: return "全拼"
      case .flypy: return "小鹤双拼"
      case .zrm: return "自然码"
      case .mspy: return "微软双拼"
      case .sogou: return "搜狗双拼"
      case .abc: return "智能ABC"
      case .ziguang: return "紫光双拼"
      case .jiajia: return "拼音加加"
      }
    }
    var iceSchema: String {
      switch self {
      case .full: return "rime_ice"
      case .zrm: return "double_pinyin"
      default: return "double_pinyin_" + rawValue
      }
    }
    var sample: String {
      switch self {
      case .full: return "nihao"
      case .flypy: return "nihc"
      case .ziguang: return "nihq"
      case .jiajia: return "nihd"
      default: return "nihk"
      }
    }
  }
  struct Asset {
    let name: String
    let url: URL
    let size: Int64
    let sha256: String
    func verify(_ file: URL) throws {
      let handle = try FileHandle(forReadingFrom: file)
      defer { try? handle.close() }
      var hash = SHA256(), count: Int64 = 0
      while let data = try handle.read(upToCount: 1024 * 1024), !data.isEmpty { hash.update(data: data); count += Int64(data.count) }
      guard count == size, hash.finalize().map({ String(format: "%02x", $0) }).joined() == sha256 else {
        throw GlintError.message("下载文件不完整或版本已变化：\(name)。请重试或更新流光方案清单。")
      }
    }
  }
  var assets: [Asset] {
    guard self == .wanxiang else { return [] }
    return [
      Asset(name: "rime-wanxiang-base.zip", url: URL(string: "https://github.com/amzxyz/rime-wanxiang/releases/download/v18.0.11/rime-wanxiang-base.zip")!,
        size: 35_217_253, sha256: "97d42dffef825385b165c13b96394f5c1bffa782e3ba91351f6afeac1101da31"),
      Asset(name: "wanxiang-lts-zh-hans.gram", url: URL(string: "https://github.com/amzxyz/RIME-LMDG/releases/download/LTS/wanxiang-lts-zh-hans.gram")!,
        size: 419_911_724, sha256: "71bc2ef5bb0d6af519ede62ca7e85c6cefa9b6916a1a09390b6924e39fdd5059"),
      Asset(name: "wanxiang-LICENSE.txt", url: URL(string: "https://raw.githubusercontent.com/amzxyz/rime-wanxiang/v18.0.11/LICENSE")!,
        size: 18_656, sha256: "9e5f1b3c610b9c2da5c313bf81d577a7d1acec686bdb0384edefa6df0f90cd94"),
      Asset(name: "wanxiang-model-LICENSE.txt", url: URL(string: "https://raw.githubusercontent.com/amzxyz/RIME-LMDG/LTS/LICENSE")!,
        size: 19_051, sha256: "cbd5af318286b74656f145dff5091907cc23d6d8c9ad09e0291ec2497792ba41")]
  }
  func isInstalled(in root: URL) -> Bool {
    if self == .ice { return true }
    return FileManager.default.fileExists(atPath: directory(in: root).appendingPathComponent("glint-package.json").path)
  }
  func installedLayout(in root: URL) -> Layout? {
    let directory = directory(in: root)
    // 读实际部署结果，避免外壳再维护一份重复的键位状态。
    guard let data = try? Data(contentsOf: directory.appendingPathComponent("build/default.yaml")),
          let config = try? RimeConfiguration.object(data),
          let list = config["schema_list"] as? [[String: Any]], let id = list.first?["schema"] as? String else { return nil }
    if self == .ice { return Layout.allCases.first { $0.iceSchema == id } }
    guard let data = try? Data(contentsOf: directory.appendingPathComponent("build/wanxiang.schema.yaml")),
          let schema = try? RimeConfiguration.object(data), let glint = schema["glint"] as? [String: Any],
          let layout = glint["layout"] as? String else { return nil }
    return Layout(rawValue: layout)
  }

  /// 只在未安装的新目录解包，绝不将公开资源覆盖进已有个人目录。
  func unpack(downloads: URL, to directory: URL) throws {
    let fm = FileManager.default
    guard self == .wanxiang, !fm.fileExists(atPath: directory.path) else { throw GlintError.message("方案安装目录已存在。") }
    for asset in assets { try asset.verify(downloads.appendingPathComponent(asset.name)) }
    try fm.createDirectory(at: directory, withIntermediateDirectories: true)
    // 仅解压上面通过固定 SHA-256 校验的官方包。使用系统 bsdtar 的路径/符号链接保护。
    let archive = downloads.appendingPathComponent(assets[0].name)
    let names = try Self.tar(["-tf", archive.path]).split(separator: "\n")
    guard names.allSatisfy({ !$0.hasPrefix("/") && !$0.contains("\\") && !$0.split(separator: "/").contains("..") }) else {
      throw GlintError.message("方案包包含目录越界路径。")
    }
    _ = try Self.tar(["-xf", archive.path, "-C", directory.path, "--no-same-owner", "--no-same-permissions"])
    guard let entries = fm.enumerator(at: directory, includingPropertiesForKeys: [.isSymbolicLinkKey]) else { throw GlintError.message("无法读取解包结果。") }
    for case let file as URL in entries {
      if try file.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == true { throw GlintError.message("方案包包含符号链接。") }
    }
    for asset in assets.dropFirst() {
      try fm.copyItem(at: downloads.appendingPathComponent(asset.name), to: directory.appendingPathComponent(asset.name))
    }
    for name in ["default.yaml", "wanxiang.schema.yaml", "wanxiang.dict.yaml", "wanxiang_algebra.yaml", "lua/wanxiang/wanxiang.lua"] {
      guard fm.fileExists(atPath: directory.appendingPathComponent(name).path) else { throw GlintError.message("方案缺少资源：\(name)") }
    }
    try RimeConfiguration.update(directory.appendingPathComponent("default.custom.yaml"), changes: [
      "schema_list": [["schema": "wanxiang"]],
      "ascii_composer/switch_key/Shift_L": "noop", "ascii_composer/switch_key/Shift_R": "noop",
      "navigator/bindings/Left": "left_by_char_no_loop", "navigator/bindings/Right": "right_by_char_no_loop"])
    try GlintPrediction.installDatabase(in: directory)
  }

  static func tar(_ arguments: [String]) throws -> String {
    let process = Process(), pipe = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/tar"); process.arguments = arguments
    // 输入服务没有终端的 UTF-8 locale；否则 bsdtar 会把正常中文文件名打印成八进制转义。
    process.environment = ProcessInfo.processInfo.environment.merging(["LC_ALL": "en_US.UTF-8"]) { _, value in value }
    process.standardOutput = pipe; process.standardError = pipe
    try process.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else { throw GlintError.message("方案解压失败：" + String(decoding: data.prefix(2000), as: UTF8.self)) }
    return String(decoding: data, as: UTF8.self)
  }

  func prepare(_ layout: Layout, root: URL, downloaded: URL?) throws {
    let fm = FileManager.default, destination = directory(in: root)
    if let downloaded {
      try configure(layout, in: downloaded)
      try JSONSerialization.data(withJSONObject: ["scheme": rawValue, "version": version,
        "source": source.absoluteString, "author": "amzxyz", "license": "CC-BY-4.0",
        "assets": assets.map { ["file": $0.name, "source": $0.url.absoluteString, "sha256": $0.sha256] }])
        .write(to: downloaded.appendingPathComponent("glint-package.json"), options: .atomic)
      try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
      guard !fm.fileExists(atPath: destination.path) else { throw GlintError.message("目标目录已存在，未覆盖；请检查方案目录后重试。") }
      try fm.moveItem(at: downloaded, to: destination)
    } else {
      guard isInstalled(in: root) else { throw GlintError.message("方案尚未安装。") }
      if installedLayout(in: root) != layout { try configure(layout, in: destination) }
    }
  }

  /// 维护队列调用，Rime 只有一个进程级运行时。
  func configure(_ layout: Layout, in directory: URL) throws {
    let store = GlintDataStore(directory: directory)
    let custom = self == .ice ? [] : ["wanxiang", "wanxiang_english", "wanxiang_mixedcode", "wanxiang_reverse"].map { $0 + ".custom.yaml" }
    try store.transaction(paths: ["default.custom.yaml", "user.yaml", "build"] + custom) { stage in
      let id = self == .ice ? layout.iceSchema : "wanxiang"
      try RimeConfiguration.update(stage.appendingPathComponent("default.custom.yaml"), changes: ["schema_list": [["schema": id]]])
      if self == .wanxiang {
        let patches: [(String, [String])] = [
          ("wanxiang", ["base/" + layout.name, "26jian"]),
          ("wanxiang_english", ["english/混合派生", "english/" + layout.name, "26jian"]),
          ("wanxiang_mixedcode", ["mixed/混合派生", "mixed/" + layout.name, "26jian"]),
          ("wanxiang_reverse", ["reverse/" + layout.name, "reverse/hspzn", "26jian"])]
        for (schema, rules) in patches {
          var changes: [String: Any] = ["speller/algebra": ["__patch": rules.map { "wanxiang_algebra:/" + $0 }]]
          if schema == "wanxiang" { changes["glint/layout"] = layout.rawValue }
          try RimeConfiguration.update(stage.appendingPathComponent(schema + ".custom.yaml"), changes: changes)
        }
      }
      try GlintDataStore.withEngine(at: stage, deploy: true) { engine in
        engine.openSession()
        guard engine.selectSchema(id) else { throw GlintError.message("方案加载失败。") }
        for scalar in layout.sample.unicodeScalars { engine.processKey(Int(scalar.value)) }
        guard !engine.candidates().candidates.isEmpty else { throw GlintError.message("方案未能生成候选，保留原方案。") }
        engine.clearComposition() // 验证不选字、不制造学习记录。
      }
      try GlintDataStore.withEngine(at: stage) { engine in
        engine.openSession()
        guard engine.schemaID == id else { throw GlintError.message("重新打开后方案选择未生效。") }
      }
    }
  }
}
