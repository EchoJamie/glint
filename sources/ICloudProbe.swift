//
//  ICloudProbe.swift
//  Glint
//
//  Copyright (C) 2026 EchoJamie <echojamieee@outlook.com>
//
//  This file is part of Glint, licensed under the GNU General Public License
//  version 3 or later. See LICENSE in the project root.
//

import Foundation

/// iCloud Drive 的**只读**探查。
///
/// 对应实施计划 §9 要求 T0.1 顺带核实的两项外部前提：
/// 一是非沙盒进程读写 `~/Library/Mobile Documents/com~apple~CloudDocs`
/// 是否触发系统授权提示、提示出现在什么时机；二是未下载的 `.icloud`
/// 占位文件在读写时的实际表现。
///
/// **刻意不做的事**：不建立同步逻辑、不写入云盘、不读取个人文件内容。
/// 按 decisions.md 3.2，正式同步排在 M4。
///
/// **必须注意的测量条件**：TCC 的授权上下文取决于进程的启动者。
/// 从终端直接运行时，进程继承终端已获得的权限，因此**测不出**输入法
/// 由 launchd 拉起时的情况。要得到真实结论，须在 `make install` 之后
/// 用 `Glint --probe-icloud` 在输入法自身的上下文里复测。
/// 本命令因此是幂等的，可反复运行对照。
enum ICloudProbe {
  private static let cloudDocs = FileManager.default.homeDirectoryForCurrentUser
    .appending(path: "Library/Mobile Documents/com~apple~CloudDocs", directoryHint: .isDirectory)

  /// 递归查找占位文件的深度上限。云盘目录可能很大，不做无界遍历。
  private static let maxSearchDepth = 4

  static func run() {
    report("iCloud Drive 只读探查")
    report("探测目录：\(cloudDocs.path)")
    report("")

    guard FileManager.default.fileExists(atPath: cloudDocs.path) else {
      report("❌ 目录不存在——本机未启用 iCloud Drive。")
      report("   结论：无法探查，同步功能在此机器上不可验证。")
      return
    }
    report("✅ 目录存在")

    checkReadability()
    report("")
    checkPlaceholders()

    report("")
    report("说明：本命令不写入云盘，也不读取任何文件内容。")
    report("      授权提示是否出现无法由进程自动判定，请对照上面的耗时与错误观察。")
  }

  /// 读一次目录。若系统弹出授权提示，这里会阻塞或失败——两者都记录耗时。
  private static func checkReadability() {
    let start = Date()
    do {
      let entries = try FileManager.default.contentsOfDirectory(atPath: cloudDocs.path)
      let elapsed = Date().timeIntervalSince(start)
      // 只报数量，不打印文件名：避免把个人目录结构写进诊断记录。
      report(String(format: "✅ 顶层可读：%d 个条目，耗时 %.0f ms", entries.count, elapsed * 1000))
      report("   无错误、无阻塞。若期间出现系统授权提示，说明本进程上下文与终端一致。")
    } catch {
      let elapsed = Date().timeIntervalSince(start)
      report(String(format: "❌ 顶层读取失败，耗时 %.0f ms", elapsed * 1000))
      report("   \(error.localizedDescription)")
    }
  }

  /// 查找未下载的占位文件。有占位文件时才能验证「读取是否会触发下载」。
  private static func checkPlaceholders() {
    var found: [String] = []
    var scanned = 0

    func walk(_ url: URL, depth: Int) {
      guard depth <= maxSearchDepth else { return }
      // 不过滤隐藏文件：未下载的占位文件本身就是以 `.` 开头的隐藏文件。
      guard let entries = try? FileManager.default.contentsOfDirectory(
        at: url,
        includingPropertiesForKeys: [.isDirectoryKey],
        options: []
      ) else { return }

      for entry in entries {
        scanned += 1
        if entry.pathExtension == "icloud" {
          found.append(entry.lastPathComponent)
          continue
        }
        let isDirectory = (try? entry.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
        if isDirectory && !isSymbolicLink(entry) {
          walk(entry, depth: depth + 1)
        }
      }
    }

    walk(cloudDocs, depth: 0)

    report("占位文件（.icloud）扫描：深度 ≤ \(maxSearchDepth)，共 \(scanned) 个条目")
    if found.isEmpty {
      report("⚠️  未发现未下载的占位文件——**此项无法验证**。")
      report("   decisions.md 3.2 记录的「未发现占位文件」与此一致。")
      report("   要验证，需要云盘中存在尚未下载到本机的文件。")
    } else {
      report("发现 \(found.count) 个占位文件，验证其在读取时的表现：")
      verifyOnePlaceholder(at: cloudDocs, names: found)
    }
  }

  /// 读一个占位文件，观察它是返回占位内容、触发下载，还是报错。
  private static func verifyOnePlaceholder(at root: URL, names: [String]) {
    // 不逐层拼接路径：直接用名称搜索，避免打印完整个人路径。
    guard let match = findFirst(named: names[0], under: root) else { return }

    report("   取样文件：\(names[0])")
    let start = Date()
    do {
      let data = try Data(contentsOf: match)
      let elapsed = Date().timeIntervalSince(start)
      report(String(format: "   读取返回 %d 字节，耗时 %.0f ms", data.count, elapsed * 1000))
      if elapsed > 1.0 {
        report("   ⏳ 耗时较长，疑似触发了按需下载。")
      }
      report("   注意：这只说明读取成功，不说明内容是否完整。正式同步前须核对条目数。")
    } catch {
      let elapsed = Date().timeIntervalSince(start)
      report(String(format: "   读取失败，耗时 %.0f ms", elapsed * 1000))
      report("   \(error.localizedDescription)")
    }
  }

  private static func findFirst(named name: String, under url: URL) -> URL? {
    guard let enumerator = FileManager.default.enumerator(
      at: url,
      includingPropertiesForKeys: nil,
      options: [],
      errorHandler: { _, _ in true }
    ) else { return nil }
    for case let item as URL in enumerator where item.lastPathComponent == name {
      return item
    }
    return nil
  }

  private static func isSymbolicLink(_ url: URL) -> Bool {
    (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink ?? false
  }

  private static func report(_ message: String) {
    print(message)
  }
}
