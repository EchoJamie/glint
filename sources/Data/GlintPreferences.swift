// Copyright (C) 2026 EchoJamie <echojamieee@outlook.com>
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

struct CandidateAppearance: Equatable {
  enum Theme: String, CaseIterable { case system, light, dark }
  var fontName: String = ""
  var fontSize: Double = 18
  var theme: Theme = .system
}

/// 只保存外壳自己的选项。Rime 开关继续保存在 Rime 的 user.yaml。
/// 写入时保留未管理字段，高级用户的扩展键不会被 Codable 重写丢失。
final class GlintPreferences {
  static let shared = GlintPreferences(directory: GlintIds.userDataURL)
  static let changed = Notification.Name("GlintPreferencesChanged")
  let directory: URL
  private var values: [String: Any] = [:]
  private(set) var loadError: String?
  var fileURL: URL { directory.appendingPathComponent("glint-settings.json") }

  init(directory: URL) { self.directory = directory }

  func reload() {
    do {
      if FileManager.default.fileExists(atPath: fileURL.path) {
        guard let object = try JSONSerialization.jsonObject(with: Data(contentsOf: fileURL)) as? [String: Any] else {
          throw GlintError.message("设置文件必须是 JSON 对象。")
        }
        values = object
      } else { values = [:] }
      loadError = nil
    } catch { loadError = error.localizedDescription }
  }

  var appearance: CandidateAppearance {
    let object = values["appearance"] as? [String: Any] ?? [:]
    return CandidateAppearance(fontName: object["fontName"] as? String ?? "",
      fontSize: min(36, max(12, object["fontSize"] as? Double ?? 18)),
      theme: CandidateAppearance.Theme(rawValue: object["theme"] as? String ?? "system") ?? .system)
  }

  func saveAppearance(_ value: CandidateAppearance) throws {
    guard (12...36).contains(value.fontSize), value.fontSize.isFinite else {
      throw GlintError.message("候选字号需在 12–36 之间。")
    }
    try update(section: "appearance", changes: ["fontName": value.fontName, "fontSize": value.fontSize, "theme": value.theme.rawValue])
  }

  var syncEnabled: Bool { (values["sync"] as? [String: Any])?["enabled"] as? Bool ?? false }
  var inputScheme: GlintInputScheme { GlintInputScheme(rawValue: (values["input"] as? [String: Any])?["scheme"] as? String ?? "") ?? .ice }
  func saveInputScheme(_ scheme: GlintInputScheme) throws { try update(section: "input", changes: ["scheme": scheme.rawValue]) }
  var syncConfiguration: Bool { (values["sync"] as? [String: Any])?["configuration"] as? Bool ?? false }
  var syncIntervalHours: Double { (values["sync"] as? [String: Any])?["intervalHours"] as? Double ?? 6 }

  func saveSync(enabled: Bool, configuration: Bool, intervalHours: Double) throws {
    guard intervalHours == 0 || (1...168).contains(intervalHours), intervalHours.isFinite else {
      throw GlintError.message("同步间隔应为 1–168 小时；0 表示关闭定时。")
    }
    try update(section: "sync", changes: ["enabled": enabled, "configuration": configuration, "intervalHours": intervalHours])
  }

  func resetAppearance() throws { try saveAppearance(CandidateAppearance()) }

  private func update(section: String, changes: [String: Any]) throws {
    reload() // 高级编辑与界面修改以磁盘最新内容为准，避免覆盖窗口打开后的修改。
    if let loadError { throw GlintError.message("设置文件无法读取，已保留原文件：\(loadError)") }
    var next = values
    var object = next[section] as? [String: Any] ?? [:]
    object.merge(changes) { _, value in value }
    next[section] = object
    let data = try JSONSerialization.data(withJSONObject: next, options: [.prettyPrinted, .sortedKeys])
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try data.write(to: fileURL, options: .atomic)
    values = next
    if Thread.isMainThread { NotificationCenter.default.post(name: Self.changed, object: self) }
    else { DispatchQueue.main.async { NotificationCenter.default.post(name: Self.changed, object: self) } }
  }
}

enum GlintError: LocalizedError {
  case message(String)
  var errorDescription: String? { switch self { case .message(let message): return message } }
}
