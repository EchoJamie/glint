//
//  RimeEngine.swift
//  Glint
//
//  Copyright (C) 2026 EchoJamie <echojamieee@outlook.com>
//
//  This file is part of Glint, licensed under the GNU General Public License
//  version 3 or later. See LICENSE in the project root.
//

import Foundation

/// librime 的 Swift 侧封装。
///
/// 只做三件事：管会话、按全局索引读候选、把选择交给引擎。
/// **不重排候选、不自己判断组句、不缓存学习数据**——顺序与结果一律由 Rime 决定
/// （docs/decisions.md 候选界面实现约束）。
final class RimeEngine {
  /// 一个候选。
  ///
  /// `index` 是**全局候选索引**，不是当前页或当前行的序号。
  /// 身份由 `(index, text, comment)` 三者共同确定：文本相同的两个候选
  /// 仍然是不同的候选，任何选择都不通过字符串反查索引
  /// （功能方案 §5 第 6、7 条）。
  struct Candidate: Equatable {
    let index: Int
    let text: String
    let comment: String?
  }

  /// 一批候选。
  struct Batch {
    let candidates: [Candidate]
    /// 继续读取时应传入的全局索引。
    let nextIndex: Int
    /// 已到末尾。
    let atEnd: Bool
    /// 调用失败——此时 `candidates` 与 `atEnd` 都不可信。
    /// **不能把失败当作「没有更多」**（功能方案 §6.2）。
    let failed: Bool
  }

  private var session: Int64 = 0
  private var started = false

  /// 一次读取的候选上限。功能方案 §6.2 建议首批 32 项作为起点，
  /// 实际以测量调整。
  static let batchSize = 32

  // MARK: - 生命周期

  /// 初始化引擎。目录必须隔离，不能指向用户正在使用的 `~/Library/Rime`。
  func start(appName: String, userDataDir: String, sharedDataDir: String?, logDir: String?) {
    guard !started else { return }
    let shared = sharedDataDir ?? userDataDir
    _ = appName.withCString { app in
      userDataDir.withCString { user in
        shared.withCString { shared in
          (logDir ?? "").withCString { log in
            glint_rime_start(app, user, shared, logDir == nil ? nil : log)
          }
        }
      }
    }
    started = true
  }

  /// 阻塞到部署完成。
  @discardableResult
  func deploy() -> Bool {
    glint_rime_deploy() == 0
  }

  func finalize() {
    closeSession()
    guard started else { return }
    glint_rime_finalize()
    started = false
  }

  deinit { finalize() }

  static var version: String {
    glint_rime_version().map { String(cString: $0) } ?? "unknown"
  }

  // MARK: - 会话

  func openSession() {
    closeSession()
    session = glint_rime_create_session()
  }

  func closeSession() {
    guard session != 0 else { return }
    glint_rime_destroy_session(session)
    session = 0
  }

  /// 会话是否仍然有效。旧会话的迟到事件据此丢弃，不能兜底选择首项。
  var isAlive: Bool { session != 0 && glint_rime_session_alive(session) == 1 }

  // MARK: - 输入

  /// 交一次按键给引擎。返回 true 表示引擎已处理，外壳不必再做别的。
  @discardableResult
  func processKey(_ keycode: Int, mask: Int = 0) -> Bool {
    guard isAlive else { return false }
    return glint_rime_process_key(session, Int32(keycode), Int32(mask)) == 1
  }

  /// 引擎当前的输入串（尚未转换的编码）。
  var input: String? {
    guard isAlive, let raw = glint_rime_get_input(session) else { return nil }
    let value = String(cString: raw)
    return value.isEmpty ? nil : value
  }

  /// 预编辑文本。
  var preedit: String? {
    guard isAlive else { return nil }
    var buffer = [CChar](repeating: 0, count: 4096)
    let written = glint_rime_get_preedit(session, &buffer, buffer.count)
    guard written > 0 else { return nil }
    return String(cString: buffer)
  }

  /// 取出**并消费**引擎的提交结果。
  ///
  /// 调用一次消费一次，否则会重复上屏（功能方案 §6.4）。
  /// 返回 nil 表示本次没有提交。
  func takeCommit() -> String? {
    guard isAlive else { return nil }
    var buffer = [CChar](repeating: 0, count: 8192)
    let written = glint_rime_commit_text(session, &buffer, buffer.count)
    guard written > 0 else { return nil }
    return String(cString: buffer)
  }

  func clearComposition() {
    guard isAlive else { return }
    glint_rime_clear_composition(session)
  }

  // MARK: - 候选

  /// 引擎当前高亮的全局候选索引。
  var highlightedIndex: Int? {
    guard isAlive else { return nil }
    let index = glint_rime_highlighted_index(session)
    return index < 0 ? nil : Int(index)
  }

  /// 从全局索引 `from` 开始读最多 `limit` 个候选。
  func candidates(from: Int = 0, limit: Int = RimeEngine.batchSize) -> Batch {
    guard isAlive else {
      return Batch(candidates: [], nextIndex: from, atEnd: false, failed: true)
    }

    var raw = GlintCandidateBatch()
    let status = glint_rime_candidates_from(session, Int64(from), Int32(limit), &raw)
    defer { glint_rime_free_batch(&raw) }

    guard status == 0, raw.error == 0, let items = raw.items else {
      return Batch(candidates: [], nextIndex: from, atEnd: false, failed: true)
    }

    var result: [Candidate] = []
    result.reserveCapacity(Int(raw.count))
    for offset in 0..<Int(raw.count) {
      let item = items[offset]
      guard let text = item.text else { continue }
      result.append(Candidate(
        index: from + offset,
        text: String(cString: text),
        comment: item.comment.map { String(cString: $0) }
      ))
    }

    return Batch(candidates: result, nextIndex: Int(raw.next_index),
                 atEnd: raw.at_end == 1, failed: false)
  }

  /// 移动高亮，不提交。
  ///
  /// 返回 false 可能只是位置没变化，**不代表失败**——不能据此强制选首项
  /// （功能方案 §6.3）。
  @discardableResult
  func highlight(index: Int) -> Bool {
    guard isAlive, index >= 0 else { return false }
    return glint_rime_highlight(session, Int64(index)) == 1
  }

  /// 确认某个全局索引的候选。成功不等于整句已提交——可能只选定当前分段。
  @discardableResult
  func select(index: Int) -> Bool {
    guard isAlive, index >= 0 else { return false }
    return glint_rime_select(session, Int64(index)) == 1
  }
}
