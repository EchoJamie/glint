// Copyright (C) 2026 EchoJamie <echojamieee@outlook.com>
// SPDX-License-Identifier: GPL-3.0-or-later
import CryptoKit
import Foundation

/// 随包资源与联想词库共用同一解包入口；已有顶层资源和用户配置不覆盖。
enum GlintBundledRime {
  static func installMissing(to directory: URL, only file: String? = nil,
                             resources: URL? = Bundle.main.resourceURL) throws {
    let fm = FileManager.default
    if let file, fm.fileExists(atPath: directory.appendingPathComponent(file).path) { return }
    guard let resources else { throw GlintError.message("应用缺少方案资源，请重新安装流光。") }
    let manifest = try String(contentsOf: resources.appendingPathComponent("rime-manifest.sha256"), encoding: .utf8)
    let entries = try manifest.split(separator: "\n").map { line -> (hash: String, path: String) in
      let fields = line.components(separatedBy: "  ")
      guard fields.count == 2, fields[0].count == 64,
            !fields[1].isEmpty, !fields[1].hasPrefix("/"),
            !fields[1].split(separator: "/").contains("..") else {
        throw GlintError.message("随包方案清单损坏，请重新安装流光。")
      }
      return (fields[0], fields[1])
    }
    guard entries.contains(where: { $0.path == "default.yaml" }),
          file == nil || entries.contains(where: { $0.path == file }) else {
      throw GlintError.message("随包方案清单缺少必要资源，请重新安装流光。")
    }
    let names = file.map { Set([$0]) } ?? Set(entries.map { String($0.path.split(separator: "/")[0]) } + ["data-manifest.sha256"])
    let missing = names.filter { !fm.fileExists(atPath: directory.appendingPathComponent($0).path) }
      .sorted { ($0 == "default.yaml" ? 1 : 0, $0) < ($1 == "default.yaml" ? 1 : 0, $1) }
    // 完整安装直接返回，不打开压缩包，也不启动解压进程。
    guard !missing.isEmpty else { return }
    try fm.createDirectory(at: directory, withIntermediateDirectories: true)
    let stage = try fm.url(for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: directory, create: true)
    defer { try? fm.removeItem(at: stage) }
    GlintLog.write("resources", "unpack_begin missing=\(missing.count)")
    // 构建时只收录普通文件；该归档和清单一同受 App 签名保护。
    _ = try GlintInputScheme.tar(["-xf", resources.appendingPathComponent("rime.tar.gz").path,
      "-C", stage.path, "--no-same-owner", "--no-same-permissions"])
    for entry in entries {
      let data = try Data(contentsOf: stage.appendingPathComponent(entry.path), options: .mappedIfSafe)
      let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
      guard hash == entry.hash else { throw GlintError.message("随包方案校验失败：\(entry.path)") }
    }
    // 完整解压、校验成功后才逐项原子移入；default.yaml 最后落地，中断后可重试。
    for name in missing {
      try fm.moveItem(at: stage.appendingPathComponent(name), to: directory.appendingPathComponent(name))
    }
    GlintLog.write("resources", "unpack_complete installed=\(missing.count)")
  }
}
