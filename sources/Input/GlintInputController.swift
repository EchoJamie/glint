// Copyright (C) 2026 EchoJamie <echojamieee@outlook.com>
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import InputMethodKit

/// 只搬运会话、按键、预编辑与选择；候选顺序、组句、提交与学习都交给 Rime。
final class GlintInputController: IMKInputController {
  // librime 初始化是进程级的；Rime session 属于各个控制器，不能共用一个 session。
  private static let runtime = RimeEngine()
  private static weak var activeController: GlintInputController?
  private(set) static var runtimeDataURL = GlintIds.userDataURL
  static let dataRootURL = GlintIds.userDataURL
  static var runtimeScheme: GlintInputScheme { runtimeDataURL == dataRootURL ? .ice : .wanxiang }

  /// 已在维护队列中验证部署后调用；保存本机选择失败时恢复原运行时。
  static func useScheme(_ scheme: GlintInputScheme) throws {
    GlintLog.write("scheme", "switch from=\(runtimeScheme.rawValue) to=\(scheme.rawValue)")
    let previous = runtimeDataURL
    let previousScheme = runtimeScheme
    runtime.finalize()
    runtimeDataURL = scheme.directory(in: dataRootURL)
    do {
      guard restartAfterMaintenance() else { throw GlintError.message("新方案无法启动。") }
      if previousScheme != scheme {
        let preferences = GlintPreferences(directory: dataRootURL)
        try preferences.saveInputScheme(scheme)
      }
    } catch {
      GlintLog.write("scheme", "switch_failed rollback=\(previousScheme.rawValue)", error: error)
      runtime.finalize(); runtimeDataURL = previous
      let restored = restartAfterMaintenance()
      GlintLog.write("scheme", "rollback_engine_ready=\(restored)")
      throw error
    }
  }
  static var hasActiveComposition: Bool {
    !GlintMaintenance.shared.isRunning && activeController?.engine.input != nil
  }

  static func suspendForMaintenance() {
    activeController?.engine.closeSession()
    activeController?.invalidateCandidates()
    runtime.finalize()
  }

  /// 正常退出前交还未完成的输入并关闭引擎；维护期间由应用代理拒绝退出。
  static func stopEngine() {
    activeController?.finishSession()
    runtime.finalize()
  }

  /// 后台维护结束后先恢复运行时，再允许主线程进入 Rime。
  static func restartAfterMaintenance() -> Bool {
    runtime.start(appName: "rime.glint", userDataDir: runtimeDataURL.path,
      sharedDataDir: runtimeDataURL.path, logDir: runtimeDataURL.appendingPathComponent("logs").path)
    guard runtime.started else { return false }
    runtime.openSession()
    let valid = runtime.isAlive && runtime.schemaID != nil && runtime.schemaID != ".default"
    runtime.closeSession()
    return valid
  }

  static func resumeAfterMaintenance() {
    if let controller = activeController, controller.inputClient != nil {
      controller.engine.openSession(allowPrediction: GlintTouchBar.isAvailable)
    }
  }

  private func scheduleMaintenance() {
    DispatchQueue.main.async { GlintMaintenance.shared.drain() }
  }
  private let engine = RimeEngine()
  private var inputClient: IMKTextInput?
  private var candidatePanel: CandidatePanel?
  // 只保存触摸开始前的高亮，用于取消恢复和拒绝跨代次的手势。
  private var touchBarOrigin: CandidateSelection?
  private var shownCandidates: [RimeEngine.Candidate] = []
  private var candidateGeneration: UInt64 = 0
  private var lastComposition: RimeEngine.Composition?
  private var nextIndex = 0
  private var atEnd = false
  private var loading = false
  private var reportedCandidateFailure = false // 每个控制器只记首次异常，避免连续失败刷日志。
  private var isActive: Bool { !GlintMaintenance.shared.isRunning && Self.activeController === self && engine.isAlive }

  override func activateServer(_ sender: Any!) {
    super.activateServer(sender)
    // 系统可能先激活新客户端，再停用旧客户端。旧组合只交还给旧客户端。
    Self.activeController?.finishSession()
    guard let client = sender as? IMKTextInput else { return }
    inputClient = client
    if GlintMaintenance.shared.isRunning {
      Self.activeController = self
      return
    }
    guard Self.startEngineIfNeeded() else { inputClient = nil; return }
    engine.openSession(allowPrediction: GlintTouchBar.isAvailable)
    guard engine.isAlive else {
      GlintLog.write("input", "session_creation_failed client=\(client.bundleIdentifier() ?? "unknown")")
      inputClient = nil; return
    }
    Self.activeController = self
    invalidateCandidates()
    setupCandidatePanel()
  }

  override func deactivateServer(_ sender: Any!) {
    finishSession()
    super.deactivateServer(sender)
  }

  override func inputControllerWillClose() {
    finishSession()
    candidatePanel?.close()
    candidatePanel = nil
    super.inputControllerWillClose()
  }

  private func finishSession() {
    commitComposition(inputClient)
    engine.closeSession()
    GlintTouchBar.hide(inputClient)
    inputClient = nil
    touchBarOrigin = nil
    invalidateCandidates()
    if Self.activeController === self { Self.activeController = nil }
    scheduleMaintenance()
  }

  override func hidePalettes() {
    invalidateCandidates()
    super.hidePalettes()
  }

  override func commitComposition(_ sender: Any!) {
    guard engine.isAlive, let client = inputClient else { return }
    // 已确认的提交与剩余原始编码分别消费；重复调用不会重复上屏。
    if let commit = engine.takeCommit() { client.insertText(commit, replacementRange: Self.replacementRange) }
    if let input = engine.input { client.insertText(input, replacementRange: Self.replacementRange) }
    engine.clearComposition()
    client.setMarkedText("", selectionRange: NSRange(location: 0, length: 0), replacementRange: Self.replacementRange)
    invalidateCandidates()
    scheduleMaintenance()
  }

  // Caps Lock 的长短按与中英文切源由 macOS 处理，不再订阅修饰键作临时记录。
  override func recognizedEvents(_ sender: Any!) -> Int { Int(NSEvent.EventTypeMask.keyDown.rawValue) }

  override func handle(_ event: NSEvent!, client sender: Any!) -> Bool {
    if GlintMaintenance.shared.isRunning {
      GlintMaintenance.shared.showInputNotice()
      return false
    }
    guard isActive, event.type == .keyDown else { return false }
    let key = MacOSKeyCode.rimeKeyCode(keycode: event.keyCode, keychar: event.characters?.first,
      shift: event.modifierFlags.contains(.shift), caps: event.modifierFlags.contains(.capsLock))
    // 联想仅供 Touch Bar 点选。键盘先撤回联想，再按无组合时的正常路径处理原键。
    if !shownCandidates.isEmpty, engine.input == nil {
      engine.processKey(0xff1b)
      flush()
    }
    guard key != 0xffffff, !event.modifierFlags.contains(.command) else { return false }
    let plain = event.modifierFlags.intersection([.shift, .control, .option, .command]).isEmpty
    if plain, !shownCandidates.isEmpty, let panel = candidatePanel {
      if key == 0xff54, panel.layout == .compact { panel.setLayout(.expanded); showPanel(); return true }
      if key == 0xff1b, panel.layout == .expanded { panel.setLayout(.compact); showPanel(); return true }
      if (0x31...0x39).contains(key) {
        panel.stopScrolling()
        if let selection = panel.numberedSelections[Int(key - 0x30)] { select(selection) }
        return true
      }
      if key == 0x20, let index = engine.highlightedIndex {
        select(CandidateSelection(generation: candidateGeneration, index: index))
        return true
      }
      if key == 0xff55 || key == 0xff56 {
        panel.stopScrolling()
        panel.setLayout(.expanded)
        let direction: CGFloat = key == 0xff55 ? -1 : 1
        if direction > 0 { loadMore() }
        panel.scroll(to: panel.viewport.minY + direction * max(36, panel.viewport.height - 36))
        return true
      }
      if [UInt32(0x2d), 0x3d, 0x5b, 0x5d].contains(key) {
        panel.stopScrolling()
        panel.setLayout(.expanded)
        let direction = (key == 0x2d || key == 0x5b) ? -1 : 1
        if direction > 0, panel.isHighlightInLastRow { loadMore() }
        if let target = panel.positionForMove(vertical: direction), let selection = panel.selection(at: target) {
          highlight(selection, reveal: true)
        }
        if direction < 0, panel.isHighlightInFirstRow { panel.setLayout(.compact) }
        return true
      }
      // 光标在拼音内部时先交 Rime 编辑；到末端后才接管左右选词。
      if (key == 0xff53 || (key == 0xff51 && !panel.isHighlightInFirstColumn)),
         engine.composition.map({ $0.caret == $0.input.utf8.count }) ?? true {
        panel.stopScrolling()
        if key == 0xff53, panel.isHighlightInLastRow { loadMore() }
        if let target = panel.positionForMove(horizontal: key == 0xff51 ? -1 : 1),
           let selection = panel.selection(at: target) { highlight(selection, reveal: true) }
        return true
      }
      if panel.layout == .expanded, key == 0xff52 || key == 0xff54 {
        panel.stopScrolling()
        if key == 0xff54, panel.isHighlightInLastRow { loadMore() }
        let target = panel.positionForMove(vertical: key == 0xff52 ? -1 : 1)
        if let target, let selection = panel.selection(at: target) { highlight(selection, reveal: true) }
        if key == 0xff52, panel.isHighlightInFirstRow { panel.setLayout(.compact) }
        return true
      }
    }
    let hadCandidates = !shownCandidates.isEmpty
    let consumed = engine.processKey(Int(key), mask: Int(MacOSKeyCode.rimeModifiers(from: event.modifierFlags)))
    // 联想没有预编辑；引擎可能撤掉联想后将按键交还宿主，也需要刷新两处候选。
    if consumed || hadCandidates { flush() }
    return consumed || engine.composition != nil
  }

  override func inputText(_ string: String!, client sender: Any!) -> Bool { false }

  // MARK: - Touch Bar 回调

  @objc(setInputMethodProperty:value:)
  func acceptTouchBarEvent(_ property: UInt, value: Any) {
    guard GlintTouchBar.isAvailable, property == 1, isActive, let event = value as? [String: Any],
          let status = (event["status"] as? NSNumber)?.intValue else { return }
    if status == 3 { finishTouchBarInteraction(); return }
    guard status == 1 || status == 2 else { return }
    // 组合改变后保留旧手势代次，直到手势结束；不能把迟到的松手套到新候选。
    if let origin = touchBarOrigin, origin.generation != candidateGeneration {
      if status == 2 { touchBarOrigin = nil }
      return
    }
    guard let index = GlintTouchBar.index(in: touchBarCandidates, event: event) else {
      if status == 2 { finishTouchBarInteraction() }
      return
    }
    let selection = CandidateSelection(generation: candidateGeneration, index: index)
    if status == 1 {
      if touchBarOrigin == nil, let previous = engine.highlightedIndex {
        touchBarOrigin = CandidateSelection(generation: candidateGeneration, index: previous)
      }
      highlight(selection, reveal: true, syncTouchBar: false)
    } else {
      touchBarOrigin = nil
      select(selection)
    }
  }

  private func finishTouchBarInteraction() {
    let origin = touchBarOrigin
    touchBarOrigin = nil
    if let origin { highlight(origin, reveal: true) }
  }

  private func publishTouchBar() {
    guard GlintTouchBar.isAvailable, isActive else { return }
    GlintTouchBar.show(touchBarCandidates, highlighted: engine.highlightedIndex, client: inputClient)
  }

  private var touchBarCandidates: [RimeEngine.Candidate] {
    let selections = candidatePanel?.numberedSelections ?? [:]
    return selections.keys.sorted().compactMap { number in
      shownCandidates.first { $0.index == selections[number]?.index }
    }
  }

  // MARK: - 候选与提交

  private func isCurrent(_ selection: CandidateSelection) -> Bool {
    isActive && selection.generation == candidateGeneration && shownCandidates.contains { $0.index == selection.index }
  }

  private func highlight(_ selection: CandidateSelection, reveal: Bool, syncTouchBar: Bool = true) {
    guard isCurrent(selection) else { return }
    _ = engine.highlight(index: selection.index)
    // highlight 返回 false 也可能只是位置未改变，实际高亮以引擎读回值为准。
    candidatePanel?.setHighlighted(shownCandidates.firstIndex { $0.index == engine.highlightedIndex }, reveal: reveal)
    if syncTouchBar { publishTouchBar() }
  }

  private func select(_ selection: CandidateSelection) {
    guard isCurrent(selection), engine.select(index: selection.index) else { return }
    // 部分确认也开启新一轮；即使文本恰好相同，旧触摸/双击仍不能再次确认。
    invalidateCandidates()
    flush()
  }

  private func flush() {
    guard isActive, let client = inputClient else { return }
    if let commit = engine.takeCommit() { client.insertText(commit, replacementRange: Self.replacementRange) }
    let composition = engine.composition
    let text = composition?.text ?? ""
    let range = NSRange(location: 0, length: text.utf16.count)
    // 明确标记组合样式。普通 NSString 经本机 IMK 桥接会把插入点变成整段选择。
    let marked = NSAttributedString(string: text,
      attributes: mark(forStyle: kTSMHiliteSelectedRawText, at: range) as? [NSAttributedString.Key: Any])
    client.setMarkedText(marked,
      selectionRange: NSRange(location: composition?.selection ?? 0, length: 0), replacementRange: Self.replacementRange)
    refreshCandidates(composition: composition)
    if composition == nil { scheduleMaintenance() }
  }

  private func invalidateCandidates() {
    candidateGeneration &+= 1
    lastComposition = nil
    shownCandidates = []
    nextIndex = 0
    atEnd = false
    candidatePanel?.orderOut(nil)
    candidatePanel?.setItems([], generation: candidateGeneration)
    if Self.activeController == nil || Self.activeController === self { GlintTouchBar.hide(inputClient) }
  }

  private func setupCandidatePanel() {
    guard candidatePanel == nil else { return }
    let panel = CandidatePanel()
    panel.onPick = { [weak self] selection in
      guard let self, self.engine.input != nil else { return }
      self.select(selection)
    }
    panel.onHighlight = { [weak self] selection in
      guard let self, self.engine.input != nil else { return }
      self.highlight(selection, reveal: false)
    }
    panel.onNeedMore = { [weak self] in self?.loadMore() }
    panel.onLayoutChanged = { [weak self] in
      self?.showPanel()
      self?.publishTouchBar()
    }
    candidatePanel = panel
  }

  private func refreshCandidates(composition: RimeEngine.Composition?) {
    // Rime 的下一词联想有候选但没有原始拼音，候选菜单才是显隐依据。
    guard engine.highlightedIndex != nil else { invalidateCandidates(); return }
    if composition != lastComposition {
      invalidateCandidates()
      lastComposition = composition
    }
    if shownCandidates.isEmpty { loadMore() }
    candidatePanel?.setHighlighted(shownCandidates.firstIndex { $0.index == engine.highlightedIndex })
    if !shownCandidates.isEmpty { showPanel() }
    publishTouchBar()
  }

  private func loadMore() {
    guard isActive, !loading, !atEnd, engine.highlightedIndex != nil else { return }
    loading = true
    defer { loading = false }
    let batch = engine.candidates(from: nextIndex)
    // 失败保留已验证的同轮候选，下一次滚动可重试；不标成末尾。
    guard !batch.failed else {
      if !reportedCandidateFailure {
        reportedCandidateFailure = true
        GlintLog.write("input", "candidate_batch_failed offset=\(nextIndex) generation=\(candidateGeneration)")
      }
      return
    }
    guard batch.atEnd || batch.nextIndex > nextIndex else { return }
    shownCandidates.append(contentsOf: batch.candidates)
    nextIndex = batch.nextIndex
    atEnd = batch.atEnd
    candidatePanel?.setItems(shownCandidates.map { .init(index: $0.index, text: $0.text, comment: $0.comment) },
                             generation: candidateGeneration)
    publishTouchBar()
  }

  // MARK: - 光标与屏幕

  private func showPanel() {
    guard let panel = candidatePanel, !shownCandidates.isEmpty else { return }
    // 上屏后的联想只呈现在 Touch Bar；屏幕浮窗仅服务正在编辑的拼音。
    guard engine.composition != nil else { panel.orderOut(nil); return }
    var caret = NSRect.zero
    if inputClient?.attributes(forCharacterIndex: 0, lineHeightRectangle: &caret) == nil || caret == .zero {
      caret = NSRect(origin: NSEvent.mouseLocation, size: .zero)
    }
    let point = NSPoint(x: caret.midX, y: caret.midY)
    guard let screen = NSScreen.screens.first(where: { $0.frame.contains(point) }) ?? NSScreen.main else { return }
    panel.constrain(to: screen.visibleFrame.size)
    panel.setFrameOrigin(Self.panelOrigin(size: panel.frame.size, caret: caret, visibleFrame: screen.visibleFrame))
    panel.orderFront(nil)
  }

  static func panelOrigin(size: NSSize, caret: NSRect, visibleFrame: NSRect) -> NSPoint {
    let below = caret.minY - size.height - 4
    let y = below >= visibleFrame.minY ? below : caret.maxY + 4
    return NSPoint(x: max(visibleFrame.minX, min(caret.minX, visibleFrame.maxX - size.width)),
                   y: max(visibleFrame.minY, min(y, visibleFrame.maxY - size.height)))
  }

  private static let replacementRange = NSRange(location: NSNotFound, length: 0)

  override func menu() -> NSMenu! {
    let menu = NSMenu()
    let item = NSMenuItem(title: "流光设置…", action: #selector(openSettings), keyEquivalent: "")
    item.target = self
    menu.addItem(item)
    return menu
  }

  @objc private func openSettings() { GlintSettingsWindow.shared.present() }

  // MARK: - 引擎启动

  static func startEngineIfNeeded() -> Bool {
    guard !runtime.started else { return true }
    GlintPreferences.shared.reload()
    let activeDirectory = GlintPreferences.shared.inputScheme.directory(in: dataRootURL)
    GlintLog.write("engine", "start scheme=\(GlintPreferences.shared.inputScheme.rawValue)")
    do {
      try GlintBundledRime.installMissing(to: dataRootURL)
      for scheme in GlintInputScheme.allCases where scheme.isInstalled(in: dataRootURL) {
        try GlintPrediction.installDatabase(in: scheme.directory(in: dataRootURL))
      }
      try FileManager.default.createDirectory(at: activeDirectory.appendingPathComponent("logs"), withIntermediateDirectories: true)
      try GlintDataStore(directory: activeDirectory).recover()
    } catch {
      GlintLog.write("engine", "prepare_failed", error: error)
      return false
    }
    runtimeDataURL = activeDirectory
    runtime.start(appName: "rime.glint", userDataDir: activeDirectory.path, sharedDataDir: activeDirectory.path,
                  logDir: activeDirectory.appendingPathComponent("logs").path)
    guard runtime.started, runtime.deploy() else {
      runtime.finalize()
      GlintLog.write("engine", "start_or_deploy_failed")
      return false
    }
    DispatchQueue.main.async { GlintSyncScheduler.shared.configure(startup: true) }
    GlintLog.write("engine", "ready scheme=\(runtimeScheme.rawValue)")
    return true
  }

}
