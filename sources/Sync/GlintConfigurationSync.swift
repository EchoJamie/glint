// Copyright (C) 2026 EchoJamie <echojamieee@outlook.com>
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// 每次配置修改发布不可变版本，父版本关系显式保留。
/// 两台离线设备同时修改时产生两个顶点，重连后报冲突，不靠最后写入覆盖对方。
struct GlintConfigurationSync {
  let store: GlintDataStore
  let cloud: URL
  static let allowedNames = ["default.custom.yaml", "rime_ice.custom.yaml",
    "double_pinyin.custom.yaml", "double_pinyin_flypy.custom.yaml", "double_pinyin_mspy.custom.yaml",
    "double_pinyin_sogou.custom.yaml", "double_pinyin_abc.custom.yaml", "double_pinyin_ziguang.custom.yaml", "double_pinyin_jiajia.custom.yaml",
    "wanxiang.custom.yaml", "wanxiang_english.custom.yaml", "wanxiang_mixedcode.custom.yaml", "wanxiang_reverse.custom.yaml"]
  private let fm = FileManager.default

  struct Revision: Codable, Equatable {
    let format: Int
    let id: String
    let name: String
    let parents: [String]
    let sha256: String?
    let content: Data? // nil 是显式删除；云端目录缺失永远不表示删除本机文件。
    init(name: String, parents: [String], content: Data?) {
      format = 1; id = UUID().uuidString; self.name = name; self.parents = parents.sorted()
      self.content = content; sha256 = content.map(GlintDataStore.hash)
    }
    func validate() throws {
      guard format == 1, GlintDataStore.safeName(id), GlintConfigurationSync.allowedNames.contains(name),
        parents.allSatisfy(GlintDataStore.safeName), !parents.contains(id), Set(parents).count == parents.count,
        sha256 == content.map(GlintDataStore.hash), content == nil || String(data: content!, encoding: .utf8) != nil else {
        throw GlintError.message("云端配置版本或完整性校验无效：\(name)")
      }
    }
  }
  struct Conflict: Codable { let name: String; let localHash: String?; let remote: [Revision] }
  // 确认必须绑定用户实际预览的内容；排队期间的修改不能被这次选择一并覆盖。
  struct Resolution { let choice: String; let reviewed: Conflict }
  struct Change { let name: String; let data: Data? }
  struct Plan {
    var changes: [Change] = []
    var publish: [Revision] = []
    var baseline: [String: Revision] = [:]
    var sourceHashes: [String: String] = [:]
    var changedNames: [String] { changes.map(\.name) }
    func apply(to directory: URL) throws {
      // 计划完成后、隔离副本建立前也可能有外部编辑；不能拿旧计划覆盖新内容。
      for (name, expected) in sourceHashes {
        let file = directory.appendingPathComponent(name)
        let actual = FileManager.default.fileExists(atPath: file.path) ? GlintDataStore.hash(try Data(contentsOf: file)) : ""
        guard actual == expected else { throw GlintError.message("同步准备期间 \(name) 已变化，请重新同步。") }
      }
      for change in changes {
        let target = directory.appendingPathComponent(change.name)
        let local = FileManager.default.fileExists(atPath: target.path) ? try Data(contentsOf: target) : nil
        let merged = try RimeConfiguration.mergingShared(change.data, into: local)
        if let data = merged { try data.write(to: target, options: .atomic) }
        else if FileManager.default.fileExists(atPath: target.path) { try FileManager.default.removeItem(at: target) }
      }
    }
    func publish(to cloud: URL) throws {
      for revision in publish {
        let folder = cloud.appendingPathComponent("configuration/" + revision.name)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try JSONEncoder().encode(revision).write(to: folder.appendingPathComponent(revision.id + ".json"), options: .atomic)
      }
    }
    func saveBaseline(to directory: URL) throws {
      try JSONEncoder().encode(baseline).write(to: directory.appendingPathComponent("glint-sync-state.json"), options: .atomic)
      let conflicts = directory.appendingPathComponent("glint-sync-conflicts.json")
      if FileManager.default.fileExists(atPath: conflicts.path) { try FileManager.default.removeItem(at: conflicts) }
    }
  }

  func plan(resolutions: [String: Resolution] = [:]) throws -> Plan {
    let stateFile = store.directory.appendingPathComponent("glint-sync-state.json")
    let stateData = fm.fileExists(atPath: stateFile.path) ? try Data(contentsOf: stateFile) : nil
    let baseline = try stateData.map { try JSONDecoder().decode([String: Revision].self, from: $0) } ?? [:]
    for (_, value) in baseline { try value.validate() }
    var result = Plan(baseline: baseline)
    result.sourceHashes[stateFile.lastPathComponent] = stateData.map(GlintDataStore.hash) ?? ""
    var conflicts: [Conflict] = []
    for name in Self.allowedNames {
      let local = store.directory.appendingPathComponent(name)
      let raw = fm.fileExists(atPath: local.path) ? try Data(contentsOf: local) : nil
      let rawHash = raw.map(GlintDataStore.hash)
      let content = try RimeConfiguration.shared(raw)
      let hash = content.map(GlintDataStore.hash)
      result.sourceHashes[name] = rawHash ?? ""
      let revisions = try readRevisions(name)
      let parents = Set(revisions.flatMap(\.parents))
      let tips = revisions.filter { !parents.contains($0.id) }
      let remote = tips.count == 1 ? tips[0] : nil
      let previous = baseline[name]
      let remoteContent = try RimeConfiguration.shared(remote?.content)
      let remoteHash = remoteContent.map(GlintDataStore.hash)
      let previousHash = try RimeConfiguration.shared(previous?.content).map(GlintDataStore.hash)
      if let resolution = resolutions[name] {
        guard resolution.reviewed.name == name, resolution.reviewed.localHash == rawHash,
          resolution.reviewed.remote.sorted(by: { $0.id < $1.id }) == tips.sorted(by: { $0.id < $1.id }) else {
          throw GlintError.message("冲突预览后版本已变化，请重新同步并预览：\(name)")
        }
      }
      if tips.isEmpty {
        // 第一次同步或云端目录被删除：保留本地，有文件才重新发布。
        if let content {
          let revision = Revision(name: name, parents: [], content: content)
          result.publish.append(revision); result.baseline[name] = revision
        }
        continue
      }
      if let remote, remoteHash == hash { result.baseline[name] = remote; continue }
      if let resolution = resolutions[name] {
        let chosen: Data?
        if resolution.choice == "local" { chosen = content }
        else if let selected = tips.first(where: { $0.id == resolution.choice }) { chosen = try RimeConfiguration.shared(selected.content) }
        else { throw GlintError.message("冲突版本已变化，请重新预览：\(name)") }
        let revision = Revision(name: name, parents: tips.map(\.id), content: chosen)
        if chosen != content { result.changes.append(Change(name: name, data: chosen)) }
        result.publish.append(revision); result.baseline[name] = revision
      } else if let remote, previousHash == hash || (previous == nil && content == nil) {
        result.changes.append(Change(name: name, data: remoteContent)); result.baseline[name] = remote
      } else if let remote, previousHash == remoteHash {
        let revision = Revision(name: name, parents: [remote.id], content: content)
        result.publish.append(revision); result.baseline[name] = revision
      } else {
        conflicts.append(Conflict(name: name, localHash: rawHash, remote: tips))
      }
    }
    if !conflicts.isEmpty {
      try JSONEncoder().encode(conflicts).write(to: store.directory.appendingPathComponent("glint-sync-conflicts.json"), options: .atomic)
      throw GlintError.message("配置存在冲突：\(conflicts.map(\.name).joined(separator: "、"))。请在同步页选择保留的版本；本机数据未改动。")
    }
    return result
  }

  private func readRevisions(_ name: String) throws -> [Revision] {
    let folder = cloud.appendingPathComponent("configuration/" + name)
    guard fm.fileExists(atPath: folder.path) else { return [] }
    let files = try fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
    var revisions: [Revision] = []
    for file in files {
      guard file.pathExtension == "json" else { throw GlintError.message("配置版本尚未下载完整：\(name)") }
      let revision = try JSONDecoder().decode(Revision.self, from: Data(contentsOf: file))
      try revision.validate()
      guard revision.name == name, file.lastPathComponent == revision.id + ".json" else { throw GlintError.message("配置版本路径不一致。") }
      revisions.append(revision)
    }
    let ids = Set(revisions.map(\.id))
    guard ids.count == revisions.count, revisions.allSatisfy({ Set($0.parents).isSubset(of: ids) }) else {
      throw GlintError.message("配置历史尚未下载完整：\(name)")
    }
    // 拓扑消除检测循环；循环不能被误判为“没有云端数据”。
    var visited = Set<String>()
    while true {
      let ready = revisions.filter { !visited.contains($0.id) && Set($0.parents).isSubset(of: visited) }
      if ready.isEmpty { break }
      visited.formUnion(ready.map(\.id))
    }
    guard visited == ids else { throw GlintError.message("配置版本历史存在循环：\(name)") }
    return revisions
  }
}
