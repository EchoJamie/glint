// Copyright (C) 2026 EchoJamie <echojamieee@outlook.com>
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Darwin

/// 只读取原目录。关闭的数据库先锁定复制，在副本生成原生快照后合并。
struct GlintMigration {
  struct Item {
    enum Kind: String { case configuration = "配置", resource = "方案资源", snapshot = "学习快照", database = "个人学习库（需退出鼠须管）" }
    let path: String
    let kind: Kind
    let size: Int
    let replaces: Bool
  }
  let source: URL
  let store: GlintDataStore
  private let fm = FileManager.default

  func preview() throws -> [Item] {
    let from = source.resolvingSymlinksInPath().standardizedFileURL
    let to = store.directory.resolvingSymlinksInPath().standardizedFileURL
    guard from != to, !from.path.hasPrefix(to.path + "/"), !to.path.hasPrefix(from.path + "/") else {
      throw GlintError.message("迁移源与流光目录不能重叠。")
    }
    guard let files = fm.enumerator(at: from, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey]) else {
      throw GlintError.message("无法读取迁移目录。")
    }
    var items: [Item] = []
    let excluded: Set<String> = ["build", "logs", ".git", ".glint-maintenance", "installation.yaml", "user.yaml", "squirrel.yaml", "squirrel.custom.yaml"]
    for case let file as URL in files {
      let values = try file.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey])
      if values.isSymbolicLink == true || excluded.contains(file.lastPathComponent) || file.lastPathComponent.hasPrefix(".") || file.lastPathComponent.hasPrefix("glint-") {
        files.skipDescendants(); continue
      }
      if file.pathExtension == "userdb" {
        files.skipDescendants()
        if values.isDirectory == true, file.deletingLastPathComponent() == from,
          GlintDataStore.safeName(file.deletingPathExtension().lastPathComponent),
          fm.fileExists(atPath: file.appendingPathComponent("CURRENT").path) {
          items.append(Item(path: file.lastPathComponent, kind: .database, size: 0, replaces: false))
        }
        continue
      }
      guard values.isDirectory != true else { continue }
      let path = String(file.path.dropFirst(from.path.count + 1))
      guard path.split(separator: "/").allSatisfy({ GlintDataStore.safeName(String($0)) }) else { continue }
      let kind: Item.Kind
      if file.lastPathComponent.hasSuffix(".userdb.txt") { kind = .snapshot }
      else if path.hasPrefix("sync/") { continue }
      else if file.lastPathComponent.hasSuffix(".custom.yaml") { kind = .configuration }
      else if ["yaml", "lua", "json", "txt", "ocd2"].contains(file.pathExtension) { kind = .resource }
      else { continue }
      items.append(Item(path: path, kind: kind, size: values.fileSize ?? 0,
        replaces: fm.fileExists(atPath: to.appendingPathComponent(path).path)))
    }
    return items.sorted { $0.path < $1.path }
  }

  func migrate(_ selected: [Item]) throws -> String {
    guard !selected.isEmpty else { throw GlintError.message("未选择迁移内容。") }
    // 打开预览后源文件可能变化，再核对可选路径并冻结本次要读的字节。
    let current = try preview()
    guard selected.allSatisfy({ item in current.contains { $0.path == item.path && $0.kind == item.kind } }) else {
      throw GlintError.message("迁移源清单已变化，请重新预览。")
    }
    var files: [(path: String, data: Data)] = []
    var snapshots: [DictionaryText] = []
    for item in selected {
      if item.kind == .database {
        try fm.createDirectory(at: store.workRoot, withIntermediateDirectories: true)
        let output = try Self.prepareSnapshot(database: source.appendingPathComponent(item.path),
          destination: store.workRoot.appendingPathComponent("snapshot-" + UUID().uuidString))
        snapshots.append(try DictionaryText(data: Data(contentsOf: output), kind: .snapshot))
        continue
      }
      let data = try Data(contentsOf: source.appendingPathComponent(item.path))
      if item.kind == .snapshot {
        let snapshot = try DictionaryText(data: data, kind: .snapshot); try snapshot.requireValid(); snapshots.append(snapshot)
      } else { files.append((item.path, data)) }
    }
    let changed = Set(files.map { String($0.path.split(separator: "/")[0]) } + snapshots.compactMap { $0.dictionary.map { $0 + ".userdb" } })
    return try store.transaction(paths: Array(changed.union(["build"])).sorted()) { stage in
      for file in files {
        let target = stage.appendingPathComponent(file.path)
        try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try file.data.write(to: target, options: .atomic)
      }
      try GlintDataStore.withEngine(at: stage, deploy: true) { _ in
        for snapshot in snapshots {
          let input = stage.appendingPathComponent("glint-migration.userdb.txt")
          try snapshot.data.write(to: input, options: .atomic)
          guard glint_rime_restore_dict(input.path) == 0 else { throw GlintError.message("学习快照合并失败。") }
          let output = try DictionaryText(data: Data(contentsOf: GlintDataStore.snapshotURL(snapshot.dictionary!)), kind: .snapshot)
          try output.requireValid()
          guard snapshot.dictionary == output.dictionary, snapshot.keys.isSubset(of: output.keys) else {
            throw GlintError.message("迁移后学习记录核对失败。")
          }
        }
      }
      return "迁移完成：\(files.count) 个配置/资源，\(snapshots.count) 份学习快照。源目录未改动，流光原文件已备份。"
    }
  }

  /// 仅在本进程 Rime 已关闭时调用；不在原目录初始化引擎，也不复制安装身份或配置。
  /// 与 LevelDB 相同的 fcntl 文件锁阻止其他进程在复制期间打开库；LOCK 本身不复制/读取。
  static func prepareSnapshot(database: URL, destination: URL) throws -> URL {
    let fm = FileManager.default
    let source = database.standardizedFileURL
    let target = destination.resolvingSymlinksInPath().standardizedFileURL
    let name = source.deletingPathExtension().lastPathComponent
    guard source.pathExtension == "userdb", GlintDataStore.safeName(name),
      source == source.resolvingSymlinksInPath(),
      !target.path.hasPrefix(source.deletingLastPathComponent().path + "/"),
      !source.path.hasPrefix(target.path + "/") else { throw GlintError.message("请使用独立的迁移目录与有效的个人词库。") }
    let fd = open(source.appendingPathComponent("LOCK").path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
    guard fd >= 0 else { throw GlintError.message("无法只读打开词库锁。") }
    defer { close(fd) }
    var lock = flock()
    lock.l_type = Int16(F_RDLCK); lock.l_whence = Int16(SEEK_SET)
    guard fcntl(fd, F_SETLK, &lock) == 0 else {
      throw GlintError.message("词库仍被使用，请退出鼠须管后重试，或选择已有原生快照。")
    }
    func files(_ directory: URL) throws -> [URL] {
      try fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        .filter { $0.lastPathComponent != "LOCK" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }
    func fingerprint(_ directory: URL) throws -> [String: String] {
      var result: [String: String] = [:]
      for file in try files(directory) {
        let values = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true else { throw GlintError.message("词库包含非普通文件，已取消迁移。") }
        result[file.lastPathComponent] = GlintDataStore.hash(try Data(contentsOf: file))
      }
      guard result["CURRENT"] != nil else { throw GlintError.message("词库缺少 CURRENT。") }
      return result
    }
    let before = try fingerprint(source)
    guard mkdir(target.path, 0o700) == 0 else { throw GlintError.message("迁移输出目录必须不存在且父目录可写。") }
    let data = target.appendingPathComponent("data")
    let copied = data.appendingPathComponent(source.lastPathComponent)
    try fm.createDirectory(at: copied, withIntermediateDirectories: true)
    for file in try files(source) { try fm.copyItem(at: file, to: copied.appendingPathComponent(file.lastPathComponent)) }
    guard try fingerprint(source) == before, try fingerprint(copied) == before else {
      throw GlintError.message("复制期间词库发生变化，已取消迁移。")
    }
    let engine = RimeEngine()
    let logs = target.appendingPathComponent("logs")
    try fm.createDirectory(at: logs, withIntermediateDirectories: true)
    engine.start(appName: "rime.glint", userDataDir: data.path, sharedDataDir: data.path, logDir: logs.path)
    defer { engine.finalize() }
    guard engine.started else { throw GlintError.message("快照引擎初始化失败。") }
    let snapshot = try DictionaryText(data: Data(contentsOf: GlintDataStore.snapshotURL(name)), kind: .snapshot)
    try snapshot.requireValid()
    guard snapshot.dictionary == name, try fingerprint(source) == before else { throw GlintError.message("快照身份或源库核对失败。") }
    let output = target.appendingPathComponent(name + ".userdb.txt")
    try snapshot.data.write(to: output, options: .atomic)
    return output
  }
}
