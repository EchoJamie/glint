// Copyright (C) 2026 EchoJamie <echojamieee@outlook.com>
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Rime 会忽略坏行，所以在合并前完整验证 UTF-8、元数据与每条记录。
/// 原生文本只含词语/编码/次数；原生快照另含 c/d/t 学习值。
struct DictionaryText {
  enum Kind { case snapshot, table }
  let data: Data
  let kind: Kind
  let entries: Int
  let invalidLines: [Int]
  let metadata: [String: String]
  let samples: [String]
  let keys: Set<String>
  var dictionary: String? { metadata["/db_name"]?.replacingOccurrences(of: ".userdb", with: "") }

  init(data: Data, kind: Kind) throws {
    guard let raw = String(data: data, encoding: .utf8), !raw.contains("\0") else { throw GlintError.message("文件不是有效的 UTF-8 文本。") }
    self.data = data; self.kind = kind
    var meta: [String: String] = [:], invalid: [Int] = [], sample: [String] = []
    var count = 0, comments = true
    var keys = Set<String>()
    let lines = raw.split(separator: "\n", omittingEmptySubsequences: false)
    for (index, rawLine) in lines.enumerated() {
      let line = String(rawLine).trimmingCharacters(in: .newlines)
      if line.isEmpty { continue }
      if comments && line.hasPrefix("#") {
        if line == "# no comment" { comments = false }
        if line.hasPrefix("#@") {
          let fields = line.dropFirst(2).split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
          if fields.count != 2 || fields[0].isEmpty || fields[1].isEmpty || meta[fields[0]] != nil { invalid.append(index + 1) }
          else { meta[fields[0]] = fields[1] }
        }
        continue
      }
      let fields = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
      var valid = (2...3).contains(fields.count) && fields.prefix(2).allSatisfy { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
      if valid && fields.count == 3 {
        if kind == .table { valid = Int32(fields[2]) != nil }
        else {
          let parts = fields[2].split(separator: " ").map(String.init)
          let values = parts.map { $0.split(separator: "=", omittingEmptySubsequences: false).map(String.init) }
          valid = values.count == 3 && values.allSatisfy { $0.count == 2 }
          if valid {
            let keys = values.map { $0[0] }
            valid = Set(keys) == Set(["c", "d", "t"])
            if valid {
              let dict = Dictionary(uniqueKeysWithValues: values.map { ($0[0], $0[1]) })
              valid = Int32(dict["c"]!) != nil && Double(dict["d"]!)?.isFinite == true && UInt64(dict["t"]!) != nil
            }
          }
        }
      } else if kind == .snapshot { valid = false }
      if valid {
        let code = kind == .snapshot ? fields[0] : fields[1]
        let phrase = kind == .snapshot ? fields[1] : fields[0]
        let key = code.trimmingCharacters(in: .whitespaces) + "\t" + phrase
        if kind == .snapshot && keys.contains(key) { invalid.append(index + 1); continue }
        keys.insert(key)
        count += 1
        if sample.count < 5 { sample.append(kind == .snapshot ? "\(fields[1]) · \(fields[0])" : "\(fields[0]) · \(fields[1])") }
      } else { invalid.append(index + 1) }
    }
    // Rime 的快照总以换行结束；不完整尾行即使表面能解析也拒绝。
    if kind == .snapshot && !raw.hasSuffix("\n") { invalid.append(lines.count) }
    entries = count; invalidLines = invalid; metadata = meta; samples = sample; self.keys = keys
  }

  func requireValid() throws {
    guard invalidLines.isEmpty else { throw GlintError.message("发现 \(invalidLines.count) 条无效记录（行 \(invalidLines.prefix(8).map(String.init).joined(separator: ", "))），未导入。") }
    if kind == .snapshot {
      guard metadata["/db_type"] == "userdb", let dictionary, GlintDataStore.safeName(dictionary),
            metadata["/user_id"] != nil, metadata["/tick"].flatMap(UInt64.init) != nil else {
        throw GlintError.message("快照缺少有效词典标识、设备标识或学习时钟。")
      }
    }
  }
}
