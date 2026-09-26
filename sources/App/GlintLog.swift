// Copyright (C) 2026 EchoJamie <echojamieee@outlook.com>
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import os

/// 服务启动时配置一次。
/// 输入线程不执行文件 I/O，也不等待队列空位；最多暂存 64 条，超量直接丢弃。
final class GlintLog {
  static var current: GlintLog?
  static func write(_ category: String, _ message: String, error: Error? = nil) {
    current?.record(category, message, error: error)
  }

  let directory: URL
  private let queue: DispatchQueue
  private let slots = DispatchSemaphore(value: 64)
  private let maxBytes: Int
  private let fallback = Logger(subsystem: GlintIds.bundleID, category: "diagnostics")
  private let formatter = ISO8601DateFormatter() // 只在串行写队列使用。

  init(directory: URL, maxBytes: Int = 1_048_576,
       queue: DispatchQueue = DispatchQueue(label: "Glint.diagnostics", qos: .utility)) {
    self.directory = directory; self.maxBytes = max(1024, maxBytes); self.queue = queue
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
  }

  @discardableResult
  func record(_ category: String, _ message: String, error: Error? = nil) -> Bool {
    guard slots.wait(timeout: .now()) == .success else { return false }
    let now = Date()
    let detail: String
    if let error {
      let value = error as NSError
      detail = "\(message) error=\(value.domain):\(value.code) \(error.localizedDescription)"
    } else { detail = message }
    // 不保存候选、按键、词典正文；错误摘要限长并折叠换行，单事件占一行。
    let text = String(decoding: detail.utf8.prefix(min(4096, maxBytes / 2)), as: UTF8.self)
      .replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: "\r", with: " ")
    let tag = String(category.prefix(32))
    queue.async {
      defer { self.slots.signal() }
      do {
        let fm = FileManager.default
        try fm.createDirectory(at: self.directory, withIntermediateDirectories: true,
          attributes: [.posixPermissions: 0o700])
        let file = self.directory.appendingPathComponent("glint.log")
        let previous = self.directory.appendingPathComponent("glint.previous.log")
        let line = "\(self.formatter.string(from: now)) pid=\(ProcessInfo.processInfo.processIdentifier) [\(tag)] \(text)\n"
        let data = Data(line.utf8)
        if fm.fileExists(atPath: file.path) {
          let size = (try fm.attributesOfItem(atPath: file.path)[.size] as? NSNumber)?.intValue ?? 0
          if size + data.count > self.maxBytes {
            if fm.fileExists(atPath: previous.path) { try fm.removeItem(at: previous) }
            try fm.moveItem(at: file, to: previous)
          }
        }
        if !fm.fileExists(atPath: file.path) {
          guard fm.createFile(atPath: file.path, contents: nil, attributes: [.posixPermissions: 0o600]) else {
            throw CocoaError(.fileWriteUnknown)
          }
        }
        let handle = try FileHandle(forWritingTo: file)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: data)
      } catch {
        // 文件日志本身失败只报告系统日志，不重试、不传播到输入或维护调用方。
        let value = error as NSError
        self.fallback.error("文件日志不可写：\(value.domain, privacy: .public):\(value.code)")
      }
    }
    return true
  }
}
