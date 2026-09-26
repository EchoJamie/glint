// Copyright (C) 2026 EchoJamie <echojamieee@outlook.com>
// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

// 构建时转换官方预测数据的查询词与候选；合并繁简转换后的重名项，保持权重排序。
let source = try String(contentsOfFile: CommandLine.arguments[1], encoding: .utf8)
guard let simplified = source.applyingTransform(StringTransform("Traditional-Simplified"), reverse: false) else {
  fatalError("系统繁简转换不可用")
}
var entries: [String: [String: Double]] = [:]
for line in simplified.split(separator: "\n") {
  let fields = line.split(whereSeparator: { $0.isWhitespace })
  guard fields.count == 3, let weight = Double(fields[2]), weight.isFinite, weight > 0 else {
    fatalError("预测数据格式无效")
  }
  entries[String(fields[0]), default: [:]][String(fields[1]), default: 0] += weight
}
let output = entries.keys.sorted().flatMap { key in
  entries[key]!.sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }
    .map { "\(key)\t\($0.key)\t\($0.value)" }
}.joined(separator: "\n") + "\n"
try output.write(toFile: CommandLine.arguments[2], atomically: true, encoding: .utf8)
print("已转换 \(entries.count) 个查询词；合并重名候选并按累计权重排序。")
