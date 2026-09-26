// Copyright (C) 2026 EchoJamie <echojamieee@outlook.com>
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import CryptoKit

/// 维护队列已关闭所有 session 和运行时后使用。隔离副本验证成功，才安装指定文件。
/// journal 在任何替换之前写入；崩溃后下次启动恢复原文件，不把半次操作当成功。
struct GlintDataStore {
  let directory: URL
  private let fm = FileManager.default
  var workRoot: URL { directory.appendingPathComponent(".glint-maintenance", isDirectory: true) }

  static func safeName(_ name: String) -> Bool {
    !name.isEmpty && name != "." && name != ".." && !name.hasPrefix(".") &&
      name.unicodeScalars.allSatisfy { CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_-.")).contains($0) }
  }

  static func hash(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }

  private static func hash(file: URL) throws -> String {
    let handle = try FileHandle(forReadingFrom: file)
    defer { try? handle.close() }
    var digest = SHA256()
    while let chunk = try handle.read(upToCount: 1024 * 1024), !chunk.isEmpty {
      digest.update(data: chunk)
    }
    return digest.finalize().map { String(format: "%02x", $0) }.joined()
  }

  func recover() throws {
    let journal = workRoot.appendingPathComponent("journal.json")
    guard fm.fileExists(atPath: journal.path) else { return }
    GlintLog.write("transaction", "recovery_begin")
    let record = try JSONDecoder().decode(Journal.self, from: Data(contentsOf: journal))
    guard record.paths.allSatisfy(Self.safeName), Self.safeName(record.id) else {
      throw GlintError.message("维护恢复记录无效；原文件未自动改动。")
    }
    let backup = workRoot.appendingPathComponent(record.id).appendingPathComponent("before")
    for name in record.paths {
      let target = directory.appendingPathComponent(name)
      let original = backup.appendingPathComponent(name)
      if record.existing.contains(name) {
        guard fm.fileExists(atPath: original.path) else { throw GlintError.message("缺少回滚备份：\(name)") }
        if fm.fileExists(atPath: target.path) { try fm.removeItem(at: target) }
        try fm.copyItem(at: original, to: target)
      } else if fm.fileExists(atPath: target.path) { try fm.removeItem(at: target) }
    }
    try fm.removeItem(at: journal)
    GlintLog.write("transaction", "recovery_complete id=\(record.id)")
  }

  private struct Journal: Codable { let id: String; let paths: [String]; let existing: [String] }

  func transaction<T>(paths: [String], _ operation: (URL) throws -> T) throws -> T {
    guard paths.allSatisfy(Self.safeName), Set(paths).count == paths.count else {
      throw GlintError.message("无效的维护目标。")
    }
    try recover()
    let id = UUID().uuidString
    GlintLog.write("transaction", "begin id=\(id) targets=\(paths.count)")
    let work = workRoot.appendingPathComponent(id, isDirectory: true)
    let stage = work.appendingPathComponent("data", isDirectory: true)
    let before = work.appendingPathComponent("before", isDirectory: true)
    try fm.createDirectory(at: stage, withIntermediateDirectories: true)
    try fm.createDirectory(at: before, withIntermediateDirectories: true)
    let excluded: Set<String> = [".glint-maintenance", ".glint-downloads", "schemes", "logs", "sync", "backups"]
    for source in try fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isSymbolicLinkKey]) {
      guard !excluded.contains(source.lastPathComponent) else { continue }
      // 不允许配置中的符号链接使隔离维护写到副本以外。
      try rejectLinks(source)
      try fm.copyItem(at: source, to: stage.appendingPathComponent(source.lastPathComponent))
    }
    let originals = try paths.map { (name: $0, hash: try Self.fingerprint(stage.appendingPathComponent($0))) }
    let result: T
    do { result = try operation(stage) }
    catch {
      GlintLog.write("transaction", "validation_failed id=\(id)", error: error)
      // 留存失败副本与日志，便于定位；不触碰正式目录。
      throw GlintError.message("验证失败，原数据保持不变：\(error.localizedDescription)\n诊断：\(work.path)")
    }
    for original in originals {
      guard try Self.fingerprint(directory.appendingPathComponent(original.name)) == original.hash else {
        throw GlintError.message("\(original.name) 在维护期间被外部修改，已取消替换；请重新操作。")
      }
    }
    var existing: [String] = []
    for name in paths {
      let source = directory.appendingPathComponent(name)
      if fm.fileExists(atPath: source.path) {
        try rejectLinks(source)
        try fm.copyItem(at: source, to: before.appendingPathComponent(name))
        existing.append(name)
      }
    }
    let journal = workRoot.appendingPathComponent("journal.json")
    try JSONEncoder().encode(Journal(id: id, paths: paths, existing: existing)).write(to: journal, options: .atomic)
    do {
      GlintLog.write("transaction", "promote_begin id=\(id)")
      for name in paths {
        let target = directory.appendingPathComponent(name)
        let source = stage.appendingPathComponent(name)
        if fm.fileExists(atPath: target.path) { try fm.removeItem(at: target) }
        if fm.fileExists(atPath: source.path) { try fm.moveItem(at: source, to: target) }
      }
      try fm.removeItem(at: journal)
    } catch {
      GlintLog.write("transaction", "promote_failed id=\(id)", error: error)
      do { try recover() } catch {
        GlintLog.write("transaction", "rollback_failed id=\(id)", error: error)
        throw GlintError.message("替换失败且回滚未完成：\(error.localizedDescription)。请保留 \(work.path)")
      }
      throw error
    }
    // before 保留为此次操作的可追溯备份；大体积隔离数据成功后可清理。
    try? fm.removeItem(at: stage)
    GlintLog.write("transaction", "complete id=\(id)")
    return result
  }

  private static func fingerprint(_ path: URL) throws -> String? {
    var isDirectory: ObjCBool = false
    let fm = FileManager.default
    guard fm.fileExists(atPath: path.path, isDirectory: &isDirectory) else { return nil }
    if !isDirectory.boolValue { return try hash(file: path) }
    let children = try fm.contentsOfDirectory(at: path, includingPropertiesForKeys: nil).sorted { $0.lastPathComponent < $1.lastPathComponent }
    let values = try children.map { $0.lastPathComponent + ":" + (try fingerprint($0) ?? "") }
    return hash(Data(values.joined(separator: "\n").utf8))
  }

  private func rejectLinks(_ path: URL) throws {
    if try path.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == true {
      throw GlintError.message("请先将符号链接替换为独立文件：\(path.lastPathComponent)")
    }
    if let enumerator = fm.enumerator(at: path, includingPropertiesForKeys: [.isSymbolicLinkKey], options: []) {
      for case let item as URL in enumerator {
        if try item.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == true {
          throw GlintError.message("隔离数据包含符号链接：\(item.lastPathComponent)")
        }
      }
    }
  }

  /// Rime 运行时进程级独占；仅从维护串行队列或隔离测试调用。
  static func withEngine<T>(at directory: URL, deploy: Bool = false, _ body: (RimeEngine) throws -> T) throws -> T {
    let engine = RimeEngine()
    let logs = directory.appendingPathComponent("logs", isDirectory: true)
    try FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
    engine.start(appName: "rime.glint", userDataDir: directory.path, sharedDataDir: directory.path, logDir: logs.path)
    defer { engine.finalize() }
    guard engine.started else { throw GlintError.message("Rime 运行时初始化失败。") }
    var syncPath = [CChar](repeating: 0, count: 8192)
    guard glint_rime_user_sync_dir(&syncPath, syncPath.count) == 0,
      URL(fileURLWithPath: String(cString: syncPath)).resolvingSymlinksInPath().path.hasPrefix(directory.resolvingSymlinksInPath().path + "/") else {
      throw GlintError.message("维护要求快照目录位于流光数据目录内；请检查 installation.yaml 的 sync_dir。")
    }
    if deploy {
      try validateSources(at: directory)
      let build = directory.appendingPathComponent("build")
      if FileManager.default.fileExists(atPath: build.path) { try FileManager.default.removeItem(at: build) }
    }
    guard !deploy || engine.deploy() else { throw GlintError.message("Rime 方案部署失败。") }
    engine.openSession()
    guard engine.isAlive, engine.schemaID != nil, engine.schemaID != ".default" else {
      throw GlintError.message("Rime 未能打开有效输入方案。")
    }
    engine.closeSession()
    return try body(engine)
  }

  private static func validateSources(at directory: URL) throws {
    guard let files = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil) else {
      throw GlintError.message("无法读取方案目录。")
    }
    for case let file as URL in files {
      if ["build", "logs", "sync", ".glint-maintenance", ".glint-downloads", "schemes"].contains(file.lastPathComponent) { files.skipDescendants(); continue }
      guard file.pathExtension == "yaml" else { continue }
      var text = try String(contentsOf: file, encoding: .utf8)
      if file.lastPathComponent.hasSuffix(".dict.yaml"),
        let end = text.range(of: "(?m)^\\.\\.\\.[ \t]*$", options: .regularExpression) {
        text = String(text[..<end.lowerBound])
      }
      guard glint_rime_validate_yaml(text) == 0 else {
        throw GlintError.message("YAML 格式错误：\(file.lastPathComponent)")
      }
    }
  }

  struct InputState {
    let schema: String
    let name: String
    let version: String
    let asciiPunctuation: Bool
    let prediction: Bool
  }
  func inputState() throws -> InputState {
    try Self.withEngine(at: directory) { engine in
      engine.openSession()
      let id = engine.schemaID ?? "未知"
      return InputState(schema: id, name: RimeEngine.schemaValue(id, key: "schema/name") ?? id,
        version: RimeEngine.schemaValue(id, key: "schema/version") ?? "未知",
        asciiPunctuation: engine.option("ascii_punct") ?? false,
        prediction: engine.option("prediction") ?? false)
    }
  }

  func savePunctuation(_ value: Bool) throws -> String {
    try transaction(paths: ["user.yaml"]) { stage in
      try Self.withEngine(at: stage) { _ in
        guard glint_rime_save_option("ascii_punct", value ? 1 : 0) == 0 else {
          throw GlintError.message("Rime 未能保存标点开关。")
        }
      }
      // 重新初始化并读回；部分高级方案不保存此选项，不能报告已应用。
      try Self.withEngine(at: stage) { engine in
        engine.openSession()
        guard engine.option("ascii_punct") == value else {
          throw GlintError.message("当前方案覆盖了标点选项，设置未生效。")
        }
      }
      return "标点设置已保存，并通过重新打开会话确认。"
    }
  }

  func dictionaryNames() throws -> [String] {
    try Self.withEngine(at: directory) { _ in
      var buffer = [CChar](repeating: 0, count: 65536)
      guard glint_rime_user_dict_names(&buffer, buffer.count) >= 0 else { throw GlintError.message("读取个人词典清单失败。") }
      return String(cString: buffer).split(separator: "\n").map(String.init).sorted()
    }
  }

  static func snapshotURL(_ name: String) throws -> URL {
    guard safeName(name), glint_rime_backup_dict(name) == 0 else { throw GlintError.message("无法生成个人词典快照：\(name)") }
    var buffer = [CChar](repeating: 0, count: 8192)
    guard glint_rime_user_sync_dir(&buffer, buffer.count) >= 0 else { throw GlintError.message("无法读取 Rime 快照目录。") }
    return URL(fileURLWithPath: String(cString: buffer)).appendingPathComponent(name + ".userdb.txt")
  }

  func exportDictionary(_ name: String, snapshot: Bool, to destination: URL) throws -> String {
    guard Self.safeName(name) else { throw GlintError.message("无效词典名称。") }
    var exportedCount: Int?
    let data: Data = try Self.withEngine(at: directory) { _ in
      if snapshot { return try Data(contentsOf: Self.snapshotURL(name)) }
      let temp = workRoot.appendingPathComponent(UUID().uuidString + ".txt")
      try fm.createDirectory(at: workRoot, withIntermediateDirectories: true)
      defer { try? fm.removeItem(at: temp) }
      let count = glint_rime_export_dict(name, temp.path)
      guard count >= 0 else { throw GlintError.message("导出失败。") }
      exportedCount = Int(count)
      return try Data(contentsOf: temp)
    }
    let preview = try DictionaryText(data: data, kind: snapshot ? .snapshot : .table)
    try preview.requireValid()
    guard exportedCount == nil || exportedCount == preview.entries else { throw GlintError.message("导出文件条目数不完整，未写入目标文件。") }
    try data.write(to: destination, options: .atomic)
    return "已导出 \(preview.entries) 条至 \(destination.lastPathComponent)。" + (snapshot ? "包含学习数据。" : "文本交换不包含完整学习历史。")
  }

  func importDictionary(_ text: DictionaryText, to name: String) throws -> String {
    try text.requireValid()
    guard Self.safeName(name), text.kind != .snapshot || text.dictionary == name else {
      throw GlintError.message("快照词典标识与目标不一致。")
    }
    return try transaction(paths: [name + ".userdb"]) { stage in
      let input = stage.appendingPathComponent("glint-import.userdb.txt")
      try text.data.write(to: input, options: .atomic)
      try Self.withEngine(at: stage) { _ in
        var expected = text.keys
        if fm.fileExists(atPath: stage.appendingPathComponent(name + ".userdb").path) {
          let original = try DictionaryText(data: Data(contentsOf: Self.snapshotURL(name)), kind: .snapshot)
          try original.requireValid(); expected.formUnion(original.keys)
        }
        if text.kind == .snapshot {
          guard glint_rime_restore_dict(input.path) == 0 else { throw GlintError.message("Rime 拒绝恢复此快照。") }
        } else {
          guard glint_rime_import_dict(name, input.path) == text.entries else { throw GlintError.message("Rime 实际导入数与预览不一致。") }
        }
        let output = try DictionaryText(data: Data(contentsOf: Self.snapshotURL(name)), kind: .snapshot)
        try output.requireValid()
        guard output.dictionary == name, expected.isSubset(of: output.keys) else { throw GlintError.message("导入后的词典标识或条目核对失败。") }
      }
      return "已合并 \(text.entries) 条到 \(name)，原库备份保留。"
    }
  }
}
