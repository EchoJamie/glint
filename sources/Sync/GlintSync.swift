// Copyright (C) 2026 EchoJamie <echojamieee@outlook.com>
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit

/// 普通 iCloud Drive 文件传输；不开独立进程，不改变 Rime 的 sync_dir。
struct GlintSync {
  let store: GlintDataStore
  let cloud: URL
  static var defaultCloud: URL {
    FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs/Glint")
  }
  private let fm = FileManager.default

  /// 原生文本与校验值在同一原子文件内，避免云端先看到 txt、后看到校验文件。
  struct Snapshot: Codable {
    let format: Int
    let installation: String
    let dictionary: String
    let count: Int
    let sha256: String
    let text: String
    init(data: Data, installation: String) throws {
      let parsed = try DictionaryText(data: data, kind: .snapshot)
      try parsed.requireValid()
      guard parsed.metadata["/user_id"] == installation, let dictionary = parsed.dictionary else {
        throw GlintError.message("快照设备标识不一致。")
      }
      format = 1; self.installation = installation; self.dictionary = dictionary
      count = parsed.entries; sha256 = GlintDataStore.hash(data); text = String(decoding: data, as: UTF8.self)
    }
    func validated() throws -> DictionaryText {
      let data = Data(text.utf8)
      let result = try DictionaryText(data: data, kind: .snapshot)
      try result.requireValid()
      guard format == 1, GlintDataStore.safeName(installation), GlintDataStore.safeName(dictionary),
        result.dictionary == dictionary, result.metadata["/user_id"] == installation,
        result.entries == count, GlintDataStore.hash(data) == sha256 else {
        throw GlintError.message("云端快照的身份、条目数或完整性校验失败。")
      }
      return result
    }
  }

  func synchronize(configuration: Bool, resolutions: [String: GlintConfigurationSync.Resolution] = [:]) throws -> String {
    let run = UUID().uuidString
    let started = ProcessInfo.processInfo.systemUptime
    var phase = "check_cloud", completed = false
    func step(_ name: String) {
      phase = name
      GlintLog.write("sync", "run=\(run) stage=\(name)")
    }
    defer {
      GlintLog.write("sync", "run=\(run) end result=\(completed ? "success" : "failed") stage=\(phase) elapsed_ms=\(Int((ProcessInfo.processInfo.systemUptime - started) * 1000))")
    }
    GlintLog.write("sync", "run=\(run) begin configuration=\(configuration)")
    guard fm.fileExists(atPath: cloud.deletingLastPathComponent().path) else {
      throw GlintError.message("iCloud Drive 目录不可用；本机数据未改动。")
    }
    try rejectCloudConflicts()
    step("read_snapshots")
    let names = try store.dictionaryNames()
    let remote = try readSnapshots()
    step("plan_configuration")
    let plan = try configuration ? GlintConfigurationSync(store: store, cloud: cloud).plan(resolutions: resolutions) : nil
    let allNames = Set(names + remote.map { $0.dictionary }).sorted()
    GlintLog.write("sync", "run=\(run) local_dictionaries=\(names.count) remote_snapshots=\(remote.count) changed_configs=\(plan?.changedNames.count ?? 0)")
    guard allNames.allSatisfy(GlintDataStore.safeName) else { throw GlintError.message("词典名称无效。") }
    var outgoing: [Snapshot] = []
    // 配置、基线及冲突记录一并提升/回滚；未变化的配置也纳入外部编辑核对。
    let configurationPaths = plan == nil ? [] : GlintConfigurationSync.allowedNames + ["glint-sync-state.json", "glint-sync-conflicts.json"]
    let paths = allNames.map { $0 + ".userdb" } + configurationPaths + (plan?.changedNames.isEmpty == false ? ["build"] : [])
    // 所有远端文件完整验证通过后，才开始改隔离副本。网络/云端写失败在提升本机库之前报错。
    step("prepare_transaction")
    try store.transaction(paths: paths) { stage in
      step("merge_and_validate")
      if let plan { try plan.apply(to: stage) }
      try GlintDataStore.withEngine(at: stage, deploy: plan?.changedNames.isEmpty == false) { _ in
        var expectedKeys: [String: Set<String>] = [:]
        for name in names {
          let original = try DictionaryText(data: Data(contentsOf: GlintDataStore.snapshotURL(name)), kind: .snapshot)
          try original.requireValid()
          expectedKeys[name] = original.keys
        }
        for snapshot in remote {
          let text = try snapshot.validated()
          let file = stage.appendingPathComponent("glint-sync-import.userdb.txt")
          expectedKeys[snapshot.dictionary, default: []].formUnion(text.keys)
          try text.data.write(to: file, options: .atomic)
          guard glint_rime_restore_dict(file.path) == 0 else { throw GlintError.message("Rime 拒绝云端快照：\(snapshot.dictionary)") }
        }
        for name in allNames {
          let file = try GlintDataStore.snapshotURL(name)
          let data = try Data(contentsOf: file)
          let parsed = try DictionaryText(data: data, kind: .snapshot)
          guard (expectedKeys[name] ?? []).isSubset(of: parsed.keys) else {
            throw GlintError.message("合并后缺少词条：\(name)，未替换本机库。")
          }
          let id = parsed.metadata["/user_id"] ?? ""
          outgoing.append(try Snapshot(data: data, installation: id))
        }
      }
      if let plan { try plan.saveBaseline(to: stage) }
      step("publish_cloud")
      try fm.createDirectory(at: cloud, withIntermediateDirectories: true)
      for snapshot in outgoing {
        let folder = cloud.appendingPathComponent("snapshots/" + snapshot.installation)
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        let path = folder.appendingPathComponent(snapshot.dictionary + ".json")
        try JSONEncoder().encode(snapshot).write(to: path, options: .atomic)
      }
      if let plan { try plan.publish(to: cloud) }
      step("promote_local")
    }
    completed = true
    return "同步完成：已合并 \(remote.count) 份快照，发布 \(outgoing.count) 份本机快照。\(configuration ? "配置已核对。" : "")"
  }

  private func readSnapshots() throws -> [Snapshot] {
    let root = cloud.appendingPathComponent("snapshots")
    guard fm.fileExists(atPath: root.path) else { return [] }
    var snapshots: [Snapshot] = []
    for device in try fm.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isSymbolicLinkKey]) {
      guard GlintDataStore.safeName(device.lastPathComponent) else { throw GlintError.message("云端含未知快照目录。") }
      for file in try fm.contentsOfDirectory(at: device, includingPropertiesForKeys: [.isSymbolicLinkKey]) {
        guard file.pathExtension == "json" else { throw GlintError.message("快照尚未下载完整或含未知文件：\(file.lastPathComponent)") }
        let snapshot = try JSONDecoder().decode(Snapshot.self, from: Data(contentsOf: file))
        _ = try snapshot.validated()
        guard snapshot.installation == device.lastPathComponent,
          file.lastPathComponent == snapshot.dictionary + ".json" else { throw GlintError.message("快照路径与标识不一致。") }
        snapshots.append(snapshot)
      }
    }
    return snapshots
  }

  private func rejectCloudConflicts() throws {
    guard fm.fileExists(atPath: cloud.path) else { return }
    let keys: Set<URLResourceKey> = [.isSymbolicLinkKey, .ubiquitousItemDownloadingStatusKey]
    guard let files = fm.enumerator(at: cloud, includingPropertiesForKeys: Array(keys)) else { throw GlintError.message("无法读取云端目录。") }
    for case let file as URL in files {
      let values = try file.resourceValues(forKeys: keys)
      guard values.isSymbolicLink != true else { throw GlintError.message("云端目录不能包含符号链接。") }
      if file.pathExtension == "icloud" || values.ubiquitousItemDownloadingStatus == .notDownloaded {
        try? fm.startDownloadingUbiquitousItem(at: file)
        throw GlintError.message("云端文件尚未下载完整，已请求下载；下次同步再试。")
      }
      if NSFileVersion.unresolvedConflictVersionsOfItem(at: file)?.isEmpty == false {
        throw GlintError.message("iCloud 存在文件版本冲突：\(file.lastPathComponent)。请先在 Finder 保留所需版本。")
      }
    }
  }
}
