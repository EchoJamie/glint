// Copyright (C) 2026 EchoJamie <echojamieee@outlook.com>
// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

/// 用 LibYAML 解析 YAML，写出 YAML 兼容的 JSON；不靠正则修改用户补丁。
enum RimeConfiguration {
  static func object(_ data: Data) throws -> [String: Any] {
    guard let text = String(data: data, encoding: .utf8), !text.contains("\0"),
          let json = glint_yaml_json(text) else { throw GlintError.message("配置不是有效的 YAML。") }
    defer { free(json) }
    guard let value = try JSONSerialization.jsonObject(with: Data(String(cString: json).utf8)) as? [String: Any] else {
      throw GlintError.message("配置根节点必须是映射。")
    }
    return value
  }
  static func encode(_ object: [String: Any]) throws -> Data {
    try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
  }
  static func patch(_ data: Data?) throws -> [String: Any] {
    let object = try data.map(Self.object) ?? [:]
    if let patch = object["patch"], !(patch is [String: Any]) { throw GlintError.message("配置 patch 必须是映射。") }
    return object["patch"] as? [String: Any] ?? [:]
  }
  static func update(_ file: URL, changes: [String: Any]) throws {
    let data = FileManager.default.fileExists(atPath: file.path) ? try Data(contentsOf: file) : nil
    var object = try data.map(Self.object) ?? [:]
    var patch = try Self.patch(data)
    patch.merge(changes) { _, value in value }; object["patch"] = patch
    try encode(object).write(to: file, options: .atomic)
  }
  /// 方案与键位只在本机选择；云端只交换其余用户补丁。
  private static func localKey(_ key: String) -> Bool {
    ["schema_list", "speller/algebra", "glint"].contains { key == $0 || key.hasPrefix($0 + "/") }
  }
  static func shared(_ data: Data?) throws -> Data? {
    guard let data else { return nil }
    var patch = try Self.patch(data).filter { !localKey($0.key) }
    if var speller = patch["speller"] as? [String: Any] {
      speller.removeValue(forKey: "algebra")
      if speller.isEmpty { patch.removeValue(forKey: "speller") } else { patch["speller"] = speller }
    }
    return patch.isEmpty ? nil : try encode(["patch": patch])
  }
  static func mergingShared(_ remote: Data?, into local: Data?) throws -> Data? {
    var patch = try Self.patch(try shared(remote))
    let localPatch = try Self.patch(local)
    for (key, value) in localPatch where localKey(key) { patch[key] = value }
    if let algebra = (localPatch["speller"] as? [String: Any])?["algebra"] {
      var speller = patch["speller"] as? [String: Any] ?? [:]
      speller["algebra"] = algebra; patch["speller"] = speller
    }
    var object = try local.map(Self.object) ?? [:]
    object["patch"] = patch
    return patch.isEmpty && object.count == 1 ? nil : try encode(object)
  }
}
