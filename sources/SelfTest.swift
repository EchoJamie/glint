//
//  SelfTest.swift
//  Glint
//
//  Copyright (C) 2026 EchoJamie <echojamieee@outlook.com>
//
//  This file is part of Glint, licensed under the GNU General Public License
//  version 3 or later. See LICENSE in the project root.
//

import Foundation

/// T0.2 的离线用例：候选身份与提交次数。
///
/// 对应实施计划 §7「逻辑用例」一行：全局索引、过期候选与触摸事件、
/// 部分组句、重复提交。用**隔离的测试数据目录**跑，不读取真实个人词条。
///
/// 这里检查的是外壳与引擎之间的契约，不是候选质量。候选排序对不对、
/// 词全不全属于 Rime 的事，用例不做价值判断。
enum SelfTest {
  static func run(testDataDir: String, verbose: Bool) -> Int32 {
    let userDir = (testDataDir as NSString).appendingPathComponent("rime")
    let logDir = (testDataDir as NSString).appendingPathComponent("log")

    guard FileManager.default.fileExists(atPath: userDir) else {
      print("❌ 找不到测试数据目录：\(userDir)")
      print("   先执行：make testdata")
      return 2
    }
    try? FileManager.default.createDirectory(atPath: logDir, withIntermediateDirectories: true)

    print("Glint 候选协议离线用例")
    print("librime \(RimeEngine.version)")
    print("测试数据：\(userDir)")
    print("（隔离目录；不读取 ~/Library/Rime，也不使用真实个人词条）")
    print("")

    let engine = RimeEngine()
    engine.start(appName: "rime.glint-selftest", userDataDir: userDir,
                 sharedDataDir: userDir, logDir: logDir)

    var results: [(name: String, passed: Bool, detail: String, covered: Bool)] = []

    /// 记一条结果。
    ///
    /// `covered: false` 用于**测试数据没有覆盖到**的情况——比如方案这次没返回
    /// 注释，同字不同注释的候选根本不存在。这时既不该记通过（没验到），
    /// 也不该记失败（不是缺陷），单独列出来，不混进通过数。
    func record(_ name: String, _ passed: Bool, _ detail: String = "", covered: Bool = true) {
      results.append((name, passed, detail, covered))
      let mark = !covered ? "⚠️ " : (passed ? "✅" : "❌")
      print("\(mark) \(name)\(detail.isEmpty ? "" : "  — \(detail)")")
    }

    // ---------------------------------------------------------------- T1
    print("── T1 引擎与会话 ──")
    let deployed = engine.deploy()
    record("部署完成", deployed, deployed ? "" : "start_maintenance 失败，见日志目录")

    engine.openSession()
    record("会话可创建", engine.isAlive)

    guard engine.isAlive else {
      print("\n会话创建失败，后续用例无法进行。")
      engine.finalize()
      return 1
    }

    // ---------------------------------------------------------------- T2
    print("\n── T2 产生候选 ──")
    let typed = type("nihao", into: engine)
    record("按键被引擎接收", typed > 0, "已交 \(typed)/5 个按键")

    let first = engine.candidates(from: 0)
    record("读到候选", !first.failed && !first.candidates.isEmpty,
           first.failed ? "调用失败" : "共 \(first.candidates.count) 项")

    if let highlighted = engine.highlightedIndex {
      record("引擎高亮索引可用", true, "highlighted=\(highlighted)")
    } else {
      record("引擎高亮索引可用", false, "取不到高亮")
    }

    if verbose {
      print("   前 5 项：")
      for candidate in first.candidates.prefix(5) {
        print("     [\(candidate.index)] \(candidate.text)"
              + (candidate.comment.map { "  // \($0)" } ?? ""))
      }
    }

    // ---------------------------------------------------------------- T3
    print("\n── T3 候选身份稳定 ──")
    let sample = Array(first.candidates.prefix(32))
    var mismatches: [String] = []
    for candidate in sample {
      let single = engine.candidates(from: candidate.index, limit: 1)
      guard let reread = single.candidates.first else {
        mismatches.append("[\(candidate.index)] 单项重读为空")
        continue
      }
      if reread.index != candidate.index
        || reread.text != candidate.text
        || reread.comment != candidate.comment {
        mismatches.append("[\(candidate.index)] 批量读到「\(candidate.text)」，"
                          + "单项重读得到「\(reread.text)」")
      }
    }
    record("按全局索引单项重读一致", mismatches.isEmpty,
           mismatches.isEmpty ? "核对 \(sample.count) 项" : mismatches.prefix(3).joined(separator: "；"))

    // ---------------------------------------------------------------- T4
    print("\n── T4 全局索引连续读取（卷轴的前提） ──")
    // 用一个候选很多的短输入，并把批次压到 5，逼出多次往返。
    // 关键点：读到的总数超过单批上限，说明读的不是「引擎当前页」，
    // 而是真正的全局列表——这正是连续卷轴成立的前提。
    engine.clearComposition()
    _ = type("ni", into: engine)
    let scrollLimit = 5
    let scroll = scanAll(engine, cap: 500, batchLimit: scrollLimit)
    if scroll.failed {
      record("跨批次连续读取", false, "中途调用失败")
    } else {
      record("连续读取超过单批（\(scrollLimit)）候选", scroll.candidates.count > scrollLimit,
             "读到 \(scroll.candidates.count) 项，atEnd=\(scroll.atEnd)")
      record("连续读取超过引擎一页", scroll.candidates.count > 9,
             "读到 \(scroll.candidates.count) 项")
      let contiguous = scroll.candidates.enumerated().allSatisfy { $0.offset == $0.element.index }
      record("全局索引连续无空洞", contiguous)
      let unique = Set(scroll.candidates.map(\.index)).count == scroll.candidates.count
      record("全局索引无重复", unique)

      // 同字不同候选：文本相同但注释不同，必须是两个不同的索引。
      // 在候选最多的这一组里找，命中概率最高。
      let withComments = scroll.candidates.filter { $0.comment != nil }
      if let (left, right) = findSameTextDifferentComment(in: scroll.candidates) {
        record("同字不同候选身份可区分", left.index != right.index,
               "「\(left.text)」出现在索引 \(left.index) 与 \(right.index)")
      } else if withComments.isEmpty {
        record("同字不同候选身份可区分",
               false,
               "本方案未返回任何注释，该场景不存在，**未覆盖**",
               covered: false)
      } else {
        record("同字不同候选身份可区分",
               false,
               "有 \(withComments.count) 项带注释，但未出现同字不同候选",
               covered: false)
      }
    }

    // ---------------------------------------------------------------- T5
    print("\n── T5 选择与提交次数 ──")
    // 重新建立 nihao 组合，让本项不依赖前面用例留下的状态。
    engine.clearComposition()
    _ = type("nihao", into: engine)
    let target = engine.candidates(from: 0).candidates.first
    if let target {
      let selected = engine.select(index: target.index)
      record("确认候选返回成功", selected, "索引 \(target.index)")

      let commit = engine.takeCommit()
      record("确认后取到提交", commit != nil, commit.map { "「\($0)」" } ?? "无提交")

      // 关键：提交只能被消费一次，否则会重复上屏。
      let second = engine.takeCommit()
      record("提交不被重复消费", second == nil,
             second.map { "第二次仍取到「\($0)」" } ?? "第二次为空")
    }

    // ---------------------------------------------------------------- T6
    print("\n── T6 部分组句 ──")
    engine.clearComposition()
    _ = type("nihaoshijie", into: engine)
    let long = engine.candidates(from: 0)
    if long.candidates.isEmpty {
      record("长输入产生候选", false, "无候选")
    } else {
      record("长输入产生候选", true, "共 \(long.candidates.count) 项（首批）")
      let partial = long.candidates[0]
      _ = engine.select(index: partial.index)
      let commit = engine.takeCommit()
      let remainingInput = engine.input
      let remaining = engine.candidates(from: 0)

      // select 成功不等于整句提交：要么上屏了，要么还有剩余组合，不能两者皆空还报成功。
      let consistent = commit != nil || remainingInput != nil || !remaining.candidates.isEmpty
      record("局部确认后状态自洽", consistent,
             "提交=\(commit.map { "「\($0)」" } ?? "无")，"
             + "剩余编码=\(remainingInput ?? "无")，"
             + "剩余候选=\(remaining.candidates.count)")

      let secondCommit = engine.takeCommit()
      record("局部确认不产生第二次提交", secondCommit == nil,
             secondCommit.map { "重复取到「\($0)」" } ?? "")
    }

    // ---------------------------------------------------------------- T7
    print("\n── T7 失效会话 ──")
    engine.closeSession()
    let dead = engine.candidates(from: 0)
    record("失效会话读取报失败（而非「没有了」）", dead.failed,
           "failed=\(dead.failed) atEnd=\(dead.atEnd)")
    record("失效会话选择被拒绝", engine.select(index: 0) == false)
    record("失效会话高亮被拒绝", engine.highlight(index: 0) == false)

    engine.finalize()

    // ---------------------------------------------------------------- 汇总
    let covered = results.filter(\.covered)
    let failed = covered.filter { !$0.passed }
    let uncovered = results.filter { !$0.covered }

    print("\n" + String(repeating: "─", count: 52))
    print("通过 \(covered.count - failed.count)/\(covered.count)"
          + (uncovered.isEmpty ? "" : "，另有 \(uncovered.count) 项未覆盖"))
    if !failed.isEmpty {
      print("失败项：")
      for item in failed {
        print("  ❌ \(item.name)\(item.detail.isEmpty ? "" : "  — \(item.detail)")")
      }
    }
    if !uncovered.isEmpty {
      print("未覆盖（测试数据没触及，**不算通过**）：")
      for item in uncovered { print("  ⚠️  \(item.name)  — \(item.detail)") }
    }
    return failed.isEmpty ? 0 : 1
  }

  // MARK: - 辅助

  /// 逐字母送入引擎，返回被引擎接收的按键数。
  private static func type(_ text: String, into engine: RimeEngine) -> Int {
    var handled = 0
    for character in text {
      guard let code = RimeKey.letter(character) else { continue }
      if engine.processKey(Int(code)) { handled += 1 }
    }
    return handled
  }

  /// 从全局索引 0 起按批读到底，直到末尾或达到上限。
  private static func scanAll(_ engine: RimeEngine, cap: Int,
                              batchLimit: Int = RimeEngine.batchSize)
    -> (candidates: [RimeEngine.Candidate], atEnd: Bool, failed: Bool) {
    var all: [RimeEngine.Candidate] = []
    var cursor = 0
    var atEnd = false

    while all.count < cap {
      let batch = engine.candidates(from: cursor, limit: batchLimit)
      if batch.failed { return (all, atEnd, true) }
      if batch.candidates.isEmpty {
        atEnd = batch.atEnd
        break
      }
      all.append(contentsOf: batch.candidates)
      atEnd = batch.atEnd
      if atEnd { break }
      guard batch.nextIndex > cursor else { break }  // 防止索引不前进导致死循环
      cursor = batch.nextIndex
    }
    return (all, atEnd, false)
  }

  /// 找出文本相同但注释不同的两个候选。
  private static func findSameTextDifferentComment(in candidates: [RimeEngine.Candidate])
    -> (RimeEngine.Candidate, RimeEngine.Candidate)? {
    var byText: [String: [RimeEngine.Candidate]] = [:]
    for candidate in candidates { byText[candidate.text, default: []].append(candidate) }
    for (_, group) in byText where group.count > 1 {
      for i in group.indices {
        for j in group.indices where j > i {
          if group[i].comment != group[j].comment { return (group[i], group[j]) }
        }
      }
    }
    return nil
  }
}
