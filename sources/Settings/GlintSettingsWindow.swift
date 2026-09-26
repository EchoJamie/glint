// Copyright (C) 2026 EchoJamie <echojamieee@outlook.com>
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import UniformTypeIdentifiers

final class GlintSettingsWindow: NSWindowController, NSTableViewDataSource, NSTableViewDelegate {
  static let shared = GlintSettingsWindow()
  private let sections = [("输入方案", "keyboard"), ("候选外观", "text.cursor"),
    ("词库与学习", "book.closed"), ("iCloud 同步", "icloud"), ("关于与诊断", "info.circle")]
  private let navigation = NSTableView()
  private var pages: [NSView] = []
  private let scheme = NSTextField(wrappingLabelWithString: "正在读取方案…")
  private var schemeChoices: [NSButton] = []
  private var schemeDetails: [NSTextField] = []
  private var schemeStates: [NSTextField] = []
  private let applyScheme = NSButton(title: "应用方案", target: nil, action: nil)
  private let inputMode = NSSegmentedControl(labels: ["全拼", "双拼"], trackingMode: .selectOne, target: nil, action: nil)
  private let layouts = NSPopUpButton()
  private let schemeProgress = NSTextField(wrappingLabelWithString: "")
  private let cancelDownload = NSButton(title: "取消下载", target: nil, action: nil)
  private var layoutRow: NSView!
  private var download: GlintSchemeDownload?
  private var switchingScheme = false
  private let status = NSTextField(wrappingLabelWithString: "")
  private let punctuation = NSSwitch()
  private let prediction = NSSwitch()
  private let fonts = NSPopUpButton()
  private let size = NSSlider(value: 18, minValue: 12, maxValue: 36, target: nil, action: nil)
  private let sizeLabel = NSTextField(labelWithString: "18 pt")
  private let theme = NSSegmentedControl(labels: ["跟随系统", "浅色", "深色"], trackingMode: .selectOne, target: nil, action: nil)
  private let previewMode = NSSegmentedControl(labels: ["单行", "展开"], trackingMode: .selectOne, target: nil, action: nil)
  private let preview = NSView()
  private var previewHeight: NSLayoutConstraint!
  private let dictionaries = NSPopUpButton()
  private let dictionaryName = NSTextField(labelWithString: "正在读取…")
  private let syncEnabled = NSSwitch()
  private let syncConfig = NSSwitch()
  private let interval = NSPopUpButton()
  private let synchronize = NSButton(title: "立即同步", target: nil, action: nil)
  private let conflicts = NSButton(title: "处理配置冲突…", target: nil, action: nil)
  private let syncStatus = NSTextField(wrappingLabelWithString: "同步默认关闭。")
  private let dataPath = NSTextField(wrappingLabelWithString: "")
  private var store: GlintDataStore { GlintDataStore(directory: GlintInputController.runtimeDataURL) }

  private init() {
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 720),
      styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
    window.title = "流光设置"
    window.contentMinSize = NSSize(width: 900, height: 720)
    window.isReleasedWhenClosed = false
    super.init(window: window)
    window.center()
    inputMode.selectedSegment = 0
    layouts.addItems(withTitles: GlintInputScheme.Layout.allCases.filter { $0 != .full }.map(\.name))
    inputMode.target = self; inputMode.action = #selector(updateSchemeControls)
    layouts.target = self; layouts.action = #selector(updateSchemeControls)
    applyScheme.target = self; applyScheme.action = #selector(saveSchema)
    cancelDownload.target = self; cancelDownload.action = #selector(cancelSchemeDownload)
    schemeProgress.font = .systemFont(ofSize: 12)
    schemeProgress.maximumNumberOfLines = 3
    punctuation.target = self; punctuation.action = #selector(savePunctuation)
    prediction.target = self; prediction.action = #selector(savePrediction)
    fonts.addItem(withTitle: "系统字体")
    fonts.addItems(withTitles: NSFontManager.shared.availableFontFamilies.sorted())
    fonts.target = self; fonts.action = #selector(appearanceChanged)
    size.target = self; size.action = #selector(appearanceChanged)
    size.setAccessibilityLabel("字号")
    size.numberOfTickMarks = 25; size.allowsTickMarkValuesOnly = true
    theme.target = self; theme.action = #selector(appearanceChanged)
    previewMode.selectedSegment = 0
    previewMode.target = self; previewMode.action = #selector(previewChanged)
    previewHeight = preview.heightAnchor.constraint(equalToConstant: 160)
    previewHeight.isActive = true
    syncEnabled.target = self; syncEnabled.action = #selector(saveSync)
    syncConfig.target = self; syncConfig.action = #selector(saveSync)
    interval.addItems(withTitles: ["仅手动", "每小时", "每 6 小时", "每 12 小时", "每天"])
    interval.target = self; interval.action = #selector(saveSync)
    synchronize.target = self; synchronize.action = #selector(syncNow)
    conflicts.target = self; conflicts.action = #selector(resolveConflicts)
    buildWindow()
    NotificationCenter.default.addObserver(self, selector: #selector(refreshStatus), name: GlintMaintenance.changed, object: nil)
    NotificationCenter.default.addObserver(self, selector: #selector(refreshSync), name: GlintSyncScheduler.changed, object: nil)
    loadControls()
    refreshStatus()
    refreshSync()
  }
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  func present() {
    loadControls()
    showWindow(nil)
    NSApplication.shared.activate(ignoringOtherApps: true)
    window?.makeKeyAndOrderFront(nil)
    reloadEngineState()
  }

  @objc private func reloadEngineState() {
    let store = self.store
    GlintMaintenance.shared.enqueue("读取方案与词典") {
      let input = try store.inputState()
      let names = try store.dictionaryNames()
      DispatchQueue.main.async {
        self.showInputState(input)
        let selected = self.dictionaries.titleOfSelectedItem
        self.dictionaries.removeAllItems(); self.dictionaries.addItems(withTitles: names)
        if let selected, names.contains(selected) { self.dictionaries.selectItem(withTitle: selected) }
        self.dictionaries.isHidden = names.count < 2
        self.dictionaryName.isHidden = names.count > 1
        self.dictionaryName.stringValue = names.first ?? "暂无个人词库"
      }
      return "当前方案和词典状态已读取。"
    }
  }

  private var selectedScheme: GlintInputScheme { GlintInputScheme.allCases[schemeChoices.firstIndex { $0.state == .on } ?? 0] }
  private var selectedLayout: GlintInputScheme.Layout {
    inputMode.selectedSegment == 0 ? .full : GlintInputScheme.Layout.allCases.filter { $0 != .full }[max(0, layouts.indexOfSelectedItem)]
  }
  private func showInputState(_ input: GlintDataStore.InputState) {
    GlintPreferences.shared.reload()
    let active = GlintInputController.runtimeScheme
    let layout = active.installedLayout(in: GlintInputController.dataRootURL)
    scheme.stringValue = "\(active.name) · \(layout?.name ?? input.name)"
    dataPath.stringValue = (store.directory.path as NSString).abbreviatingWithTildeInPath
    if !switchingScheme {
      for (index, choice) in schemeChoices.enumerated() { choice.state = GlintInputScheme.allCases[index] == active ? .on : .off }
      loadSchemeLayout()
    }
    punctuation.state = input.asciiPunctuation ? .on : .off
    prediction.state = GlintTouchBar.isAvailable && input.prediction ? .on : .off
    updateSchemeControls()
  }
  @objc private func schemeChanged(_ sender: NSButton) {
    for choice in schemeChoices { choice.state = choice === sender ? .on : .off }
    loadSchemeLayout()
  }
  private func loadSchemeLayout() {
    let layout = selectedScheme.installedLayout(in: GlintInputController.dataRootURL) ?? .full
    inputMode.selectedSegment = layout == .full ? 0 : 1
    if layout != .full { layouts.selectItem(at: GlintInputScheme.Layout.allCases.filter { $0 != .full }.firstIndex(of: layout)!) }
    updateSchemeControls()
  }
  @objc private func updateSchemeControls() {
    let busy = switchingScheme || GlintMaintenance.shared.isRunning || GlintMaintenance.shared.phase == .waiting
    prediction.isEnabled = !busy && GlintTouchBar.isAvailable
    schemeChoices.forEach { $0.isEnabled = !busy }; inputMode.isEnabled = !busy; layouts.isEnabled = !busy
    layoutRow.isHidden = inputMode.selectedSegment != 1
    let family = selectedScheme, root = GlintInputController.dataRootURL
    let installed = family.isInstalled(in: root)
    let current = GlintInputController.runtimeScheme == family && family.installedLayout(in: root) == selectedLayout
    applyScheme.title = current ? "已在使用" : installed ? "使用此方案" : "下载并使用"
    applyScheme.isEnabled = !busy && !current
    applyScheme.bezelColor = applyScheme.isEnabled ? .controlAccentColor : nil
    applyScheme.contentTintColor = applyScheme.isEnabled ? .white : nil
    cancelDownload.isHidden = download == nil
    for (index, item) in GlintInputScheme.allCases.enumerated() {
      let installed = item.isInstalled(in: root)
      let size = ByteCountFormatter.string(fromByteCount: item.assets.reduce(0) { $0 + $1.size }, countStyle: .file)
      schemeDetails[index].stringValue = item == .ice ? "内置 · 支持全拼和常见双拼" : item.version + " · " + (installed ? "已安装，可离线使用" : "首次下载约 \(size)")
      schemeStates[index].stringValue = GlintInputController.runtimeScheme == item ? "使用中" : ""
    }
  }
  @objc private func openSchemeSource() { NSWorkspace.shared.open(selectedScheme.source) }
  @objc private func cancelSchemeDownload() { download?.cancel(); cancelDownload.isEnabled = false }
  @objc private func saveSchema() {
    guard !switchingScheme else { return }
    let family = selectedScheme, layout = selectedLayout, root = GlintInputController.dataRootURL
    switchingScheme = true
    if family.isInstalled(in: root) { apply(family, layout: layout, prepared: nil); return }
    schemeProgress.stringValue = "正在连接官方发布源…"
    cancelDownload.isEnabled = true
    download = GlintSchemeDownload(scheme: family, root: root, progress: { self.schemeProgress.stringValue = $0 }) { result in
      self.download = nil
      switch result {
      case .success(let directory): self.apply(family, layout: layout, prepared: directory)
      case .failure(let error):
        self.switchingScheme = false
        self.schemeProgress.stringValue = error is CancellationError ? "已取消，当前方案保持不变。" : error.localizedDescription
        self.updateSchemeControls()
      }
    }
    updateSchemeControls(); download?.start()
  }
  private func apply(_ family: GlintInputScheme, layout: GlintInputScheme.Layout, prepared: URL?) {
    let root = GlintInputController.dataRootURL
    schemeProgress.stringValue = "等待当前输入结束后应用…"
    updateSchemeControls()
    GlintMaintenance.shared.enqueue("应用\(family.name)", completion: { success in
      self.switchingScheme = false
      self.schemeProgress.stringValue = GlintMaintenance.shared.detail
      if success { self.reloadEngineState() }
      self.updateSchemeControls()
    }) {
      let fm = FileManager.default
      defer { if let prepared { try? fm.removeItem(at: prepared.deletingLastPathComponent()) } }
      try family.prepare(layout, root: root, downloaded: prepared)
      try GlintInputController.useScheme(family)
      return "已使用\(family.name) · \(layout.name)。个人学习数据已保留。"
    }
  }

  private func loadControls() {
    let prefs = GlintPreferences.shared
    prefs.reload()
    let appearance = prefs.appearance
    fonts.selectItem(withTitle: appearance.fontName.isEmpty ? "系统字体" : appearance.fontName)
    size.doubleValue = appearance.fontSize
    theme.selectedSegment = CandidateAppearance.Theme.allCases.firstIndex(of: appearance.theme) ?? 0
    syncEnabled.state = prefs.syncEnabled ? .on : .off
    syncConfig.state = prefs.syncConfiguration ? .on : .off
    interval.selectItem(at: [0.0, 1, 6, 12, 24].firstIndex(of: prefs.syncIntervalHours) ?? 2)
    showPreview(appearance)
    updateSyncControls()
  }
  private var selectedAppearance: CandidateAppearance {
    CandidateAppearance(fontName: fonts.indexOfSelectedItem == 0 ? "" : fonts.titleOfSelectedItem ?? "",
      fontSize: size.doubleValue, theme: CandidateAppearance.Theme.allCases[max(0, theme.selectedSegment)])
  }
  private func showPreview(_ value: CandidateAppearance) {
    sizeLabel.stringValue = "\(Int(value.fontSize)) pt"
    preview.subviews.forEach { $0.removeFromSuperview() }
    let content = CandidatePanel.preview(value, expanded: previewMode.selectedSegment == 1)
    previewHeight.constant = max(160, content.frame.height + 72)
    let composition = NSTextField(labelWithString: "ni hao│")
    composition.font = .systemFont(ofSize: 23)
    composition.setAccessibilityLabel("预览拼音 ni hao，光标在末尾")
    preview.addSubview(composition)
    preview.addSubview(content)
    composition.translatesAutoresizingMaskIntoConstraints = false
    content.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([composition.leadingAnchor.constraint(equalTo: preview.leadingAnchor, constant: 18),
      composition.topAnchor.constraint(equalTo: preview.topAnchor, constant: 16),
      content.leadingAnchor.constraint(equalTo: composition.leadingAnchor),
      content.topAnchor.constraint(equalTo: composition.bottomAnchor, constant: 10),
      content.widthAnchor.constraint(equalToConstant: content.frame.width),
      content.heightAnchor.constraint(equalToConstant: content.frame.height)])
  }
  @objc private func previewChanged() { showPreview(selectedAppearance) }
  @objc private func appearanceChanged() {
    do { try GlintPreferences.shared.saveAppearance(selectedAppearance); showPreview(selectedAppearance); status.stringValue = "候选外观已生效。" }
    catch { report(error) }
  }
  @objc private func resetAppearance() {
    do { try GlintPreferences.shared.resetAppearance(); loadControls(); status.stringValue = "候选外观已恢复默认。" }
    catch { report(error) }
  }
  @objc private func savePunctuation() {
    let value = punctuation.state == .on, store = self.store
    GlintMaintenance.shared.enqueue("应用标点设置") {
      defer {
        if let actual = try? store.inputState() {
          DispatchQueue.main.async { self.punctuation.state = actual.asciiPunctuation ? .on : .off }
        }
      }
      return try store.savePunctuation(value)
    }
  }
  @objc private func refreshStatus() {
    status.stringValue = GlintMaintenance.shared.detail
    punctuation.isEnabled = !GlintMaintenance.shared.isRunning
    updateSchemeControls()
    updateSyncControls()
  }
  @objc private func savePrediction() {
    let value = prediction.state == .on, store = self.store, scheme = GlintInputController.runtimeScheme
    GlintMaintenance.shared.enqueue("应用上屏后联想") {
      defer {
        if let actual = try? store.inputState() {
          DispatchQueue.main.async { self.prediction.state = actual.prediction ? .on : .off }
        }
      }
      return try store.savePrediction(value, scheme: scheme)
    }
  }
  @objc private func openData() { NSWorkspace.shared.open(store.directory) }
  @objc private func openLogs() { NSWorkspace.shared.open(GlintInputController.dataRootURL.appendingPathComponent("logs")) }
  @objc private func backup() { export(snapshot: true) }
  @objc private func exportText() { export(snapshot: false) }
  private func export(snapshot: Bool) {
    guard let name = dictionaries.titleOfSelectedItem else { status.stringValue = "当前还没有个人词典，请先输入并选择候选。"; return }
    let panel = NSSavePanel()
    panel.nameFieldStringValue = name + (snapshot ? ".userdb.txt" : ".txt")
    guard panel.runModal() == .OK, let url = panel.url else { return }
    let store = self.store
    GlintMaintenance.shared.enqueue(snapshot ? "备份个人词典" : "导出词条") { try store.exportDictionary(name, snapshot: snapshot, to: url) }
  }
  @objc private func restore() { importDictionary(snapshot: true) }
  @objc private func importText() { importDictionary(snapshot: false) }
  private func importDictionary(snapshot: Bool) {
    let panel = NSOpenPanel(); panel.allowsMultipleSelection = false; panel.canChooseDirectories = false
    panel.allowedContentTypes = [.plainText]
    guard panel.runModal() == .OK, let url = panel.url else { return }
    do {
      let text = try DictionaryText(data: Data(contentsOf: url), kind: snapshot ? .snapshot : .table)
      let name = snapshot ? text.dictionary : dictionaries.titleOfSelectedItem
      guard let name else { throw GlintError.message("请先选择目标个人词典。") }
      let alert = NSAlert()
      alert.messageText = "导入预览 · \(name)"
      alert.informativeText = "有效 \(text.entries) 条 · 无效 \(text.invalidLines.count) 条\n" + text.samples.joined(separator: "\n") + "\n\n将合并到流光个人词典，保留原库备份。"
      alert.addButton(withTitle: "合并导入"); alert.addButton(withTitle: "取消")
      try text.requireValid()
      guard alert.runModal() == .alertFirstButtonReturn else { return }
      let store = self.store
      GlintMaintenance.shared.enqueue("合并个人词典") { try store.importDictionary(text, to: name) }
    } catch { report(error) }
  }
  @objc private func manageProfessional() {
    do {
      let manager = GlintProfessionalDictionary(store: store)
      let entries = try manager.entries()
      let alert = NSAlert(); alert.messageText = "专业词库"
      alert.informativeText = "与 rime_ice 全拼词典合用。启停只影响候选，保留个人学习。导入时请一起选择依赖词典。"
      let choices = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 420, height: 28))
      choices.addItems(withTitles: entries.map { ($0.enabled ? "已启用 · " : "已停用 · ") + $0.name })
      alert.accessoryView = choices
      alert.addButton(withTitle: "导入词库…")
      alert.addButton(withTitle: "切换启停").isEnabled = !entries.isEmpty
      alert.addButton(withTitle: "导出所选…").isEnabled = !entries.isEmpty
      alert.addButton(withTitle: "关闭")
      let result = alert.runModal()
      if result == .alertFirstButtonReturn {
        let panel = NSOpenPanel(); panel.allowsMultipleSelection = true; panel.canChooseDirectories = false
        guard panel.runModal() == .OK else { return }
        let resources = try panel.urls.map { try GlintProfessionalDictionary.Resource(file: $0.lastPathComponent, data: Data(contentsOf: $0)) }
        try manager.validate(resources)
        let preview = NSAlert(); preview.messageText = "导入专业词库预览"
        preview.informativeText = resources.map { "\($0.file)：\($0.entries) 条，依赖 \($0.dependencies.joined(separator: "、"))" }.joined(separator: "\n") + "\n\n编码须与全拼方案兼容；将先在隔离副本编译验证。"
        preview.addButton(withTitle: "导入并启用"); preview.addButton(withTitle: "取消")
        guard preview.runModal() == .alertFirstButtonReturn else { return }
        GlintMaintenance.shared.enqueue("应用专业词库") { try manager.install(resources) }
      } else if result.rawValue == NSApplication.ModalResponse.alertFirstButtonReturn.rawValue + 1,
                entries.indices.contains(choices.indexOfSelectedItem) {
        let selected = entries[choices.indexOfSelectedItem]
        GlintMaintenance.shared.enqueue(selected.enabled ? "停用专业词库" : "启用专业词库") {
          try manager.setEnabled(selected.name, enabled: !selected.enabled)
        }
      } else if result.rawValue == NSApplication.ModalResponse.alertFirstButtonReturn.rawValue + 2,
                entries.indices.contains(choices.indexOfSelectedItem) {
        let selected = entries[choices.indexOfSelectedItem]
        let panel = NSSavePanel(); panel.nameFieldStringValue = selected.name + "-词库"
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        status.stringValue = try manager.export(selected.name, to: destination)
      }
    } catch { report(error) }
  }

  @objc private func migrate() {
    let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false
    panel.message = "选择鼠须管数据目录。迁移个人学习库前请退出鼠须管。"
    panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Rime")
    guard panel.runModal() == .OK, let source = panel.url else { return }
    do {
      let migration = GlintMigration(source: source, store: store)
      let items = try migration.preview()
      let alert = NSAlert(); alert.messageText = "迁移预览"
      alert.informativeText = "勾选要迁入的文件及方案依赖。标记“替换”的文件将先备份。个人学习库会在独立副本生成快照再合并；正在使用的库会拒绝迁移。鼠须管原目录不改动。"
      let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 560, height: 300))
      scroll.hasVerticalScroller = true
      let document = NSView(frame: NSRect(x: 0, y: 0, width: 540, height: max(300, items.count * 28)))
      var controls: [NSButton] = []
      for (index, item) in items.enumerated() {
        let checkbox = NSButton(checkboxWithTitle: "\(item.kind.rawValue) · \(item.path)\(item.replaces ? "（替换）" : "")", target: nil, action: nil)
        checkbox.frame = NSRect(x: 0, y: document.frame.height - CGFloat((index + 1) * 28), width: 540, height: 26)
        document.addSubview(checkbox); controls.append(checkbox)
      }
      scroll.documentView = document; alert.accessoryView = scroll
      alert.addButton(withTitle: "迁入所选文件"); alert.addButton(withTitle: "取消")
      guard alert.runModal() == .alertFirstButtonReturn else { return }
      let selected = items.enumerated().filter { controls[$0.offset].state == .on }.map(\.element)
      guard !selected.isEmpty else { return }
      GlintMaintenance.shared.enqueue("迁移配置与学习") { try migration.migrate(selected) }
    } catch { report(error) }
  }

  @objc private func saveSync() {
    do {
      try GlintPreferences.shared.saveSync(enabled: syncEnabled.state == .on, configuration: syncConfig.state == .on,
        intervalHours: [0.0, 1, 6, 12, 24][max(0, interval.indexOfSelectedItem)])
      syncStatus.stringValue = syncEnabled.state == .on ? "同步已开启。" : "同步已关闭，本机与云端数据保留。"
      GlintSyncScheduler.shared.configure()
      updateSyncControls()
    } catch { report(error) }
  }
  @objc private func refreshSync() {
    syncStatus.stringValue = GlintSyncScheduler.shared.detail
    updateSyncControls()
  }
  private func updateSyncControls() {
    let enabled = syncEnabled.state == .on
    syncConfig.isEnabled = enabled
    interval.isEnabled = enabled
    synchronize.isEnabled = enabled && !GlintMaintenance.shared.isRunning && GlintMaintenance.shared.phase != .waiting
    let file = store.directory.appendingPathComponent("glint-sync-conflicts.json")
    conflicts.isHidden = !FileManager.default.fileExists(atPath: file.path)
  }
  @objc private func resolveConflicts() {
    do {
      let file = store.directory.appendingPathComponent("glint-sync-conflicts.json")
      guard FileManager.default.fileExists(atPath: file.path) else { syncStatus.stringValue = "当前没有配置冲突。"; return }
      let conflicts = try JSONDecoder().decode([GlintConfigurationSync.Conflict].self, from: Data(contentsOf: file))
      var decisions: [String: GlintConfigurationSync.Resolution] = [:]
      for conflict in conflicts {
        let alert = NSAlert()
        alert.messageText = "处理冲突 · " + conflict.name
        alert.informativeText = "选择要保留的版本。其余版本仍保留在云端历史中；应用前将验证部署。"
        let choices = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 420, height: 28))
        choices.addItem(withTitle: "保留本机文件")
        for revision in conflict.remote {
          choices.addItem(withTitle: "云端 " + revision.id.prefix(8) + (revision.content == nil ? "（删除）" : " · " + String(revision.content!.count) + " 字节"))
        }
        let text = NSTextView(frame: NSRect(x: 0, y: 38, width: 420, height: 220))
        text.isEditable = false; text.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        let local = store.directory.appendingPathComponent(conflict.name)
        let localData = FileManager.default.fileExists(atPath: local.path) ? try Data(contentsOf: local) : nil
        let reviewed = GlintConfigurationSync.Conflict(name: conflict.name,
          localHash: localData.map(GlintDataStore.hash), remote: conflict.remote)
        text.string = "本机：\n" + (localData.map { String(decoding: $0, as: UTF8.self) } ?? "（已删除）") + "\n\n" + conflict.remote.map {
          "云端 " + $0.id.prefix(8) + "：\n" + ($0.content.flatMap { String(data: $0, encoding: .utf8) } ?? "（删除）")
        }.joined(separator: "\n\n")
        let accessory = NSView(frame: NSRect(x: 0, y: 0, width: 420, height: 270))
        let scroll = NSScrollView(frame: text.frame); scroll.hasVerticalScroller = true; scroll.documentView = text
        text.isVerticallyResizable = true; text.autoresizingMask = [.width]; accessory.addSubview(scroll); accessory.addSubview(choices)
        alert.accessoryView = accessory
        alert.addButton(withTitle: "使用所选版本"); alert.addButton(withTitle: "取消")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let choice = choices.indexOfSelectedItem == 0 ? "local" : conflict.remote[choices.indexOfSelectedItem - 1].id
        decisions[conflict.name] = .init(choice: choice, reviewed: reviewed)
      }
      GlintSyncScheduler.shared.request(resolutions: decisions)
    } catch { report(error) }
  }
  @objc private func syncNow() { GlintSyncScheduler.shared.request() }
  private func report(_ error: Error) {
    GlintLog.write("settings", "operation_failed", error: error)
    status.stringValue = error.localizedDescription
  }

  private func buildWindow() {
    let root = NSView(), main = NSView(), sidebar = NSVisualEffectView()
    window?.contentView = root
    sidebar.material = .sidebar; sidebar.blendingMode = .withinWindow
    let separator = NSBox(); separator.boxType = .separator
    for view in [sidebar, separator, main] { root.addSubview(view); view.translatesAutoresizingMaskIntoConstraints = false }
    NSLayoutConstraint.activate([sidebar.leadingAnchor.constraint(equalTo: root.leadingAnchor),
      sidebar.topAnchor.constraint(equalTo: root.topAnchor), sidebar.bottomAnchor.constraint(equalTo: root.bottomAnchor),
      sidebar.widthAnchor.constraint(equalToConstant: 184),
      separator.leadingAnchor.constraint(equalTo: sidebar.trailingAnchor), separator.widthAnchor.constraint(equalToConstant: 1),
      separator.topAnchor.constraint(equalTo: root.topAnchor), separator.bottomAnchor.constraint(equalTo: root.bottomAnchor),
      main.leadingAnchor.constraint(equalTo: separator.trailingAnchor), main.trailingAnchor.constraint(equalTo: root.trailingAnchor),
      main.topAnchor.constraint(equalTo: root.topAnchor), main.bottomAnchor.constraint(equalTo: root.bottomAnchor)])

    let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("section"))
    navigation.addTableColumn(column); navigation.headerView = nil
    navigation.backgroundColor = .clear; navigation.style = .sourceList
    navigation.rowHeight = 38; navigation.intercellSpacing = NSSize(width: 0, height: 4)
    navigation.dataSource = self; navigation.delegate = self
    navigation.allowsEmptySelection = false
    navigation.setAccessibilityLabel("设置分类")
    let list = NSScrollView(); list.drawsBackground = false; list.documentView = navigation
    sidebar.addSubview(list); list.translatesAutoresizingMaskIntoConstraints = false
    let current = vertical([note("当前输入方案"), scheme], spacing: 4)
    scheme.font = .systemFont(ofSize: 12, weight: .medium)
    sidebar.addSubview(current)
    NSLayoutConstraint.activate([list.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: 8),
      list.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor, constant: -8),
      list.topAnchor.constraint(equalTo: sidebar.topAnchor, constant: 16), list.heightAnchor.constraint(equalToConstant: 230),
      current.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: 18),
      current.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor, constant: -14),
      current.bottomAnchor.constraint(equalTo: sidebar.bottomAnchor, constant: -22)])

    let schemeRows = GlintInputScheme.allCases.enumerated().map { index, family -> NSView in
      let choice = NSButton(radioButtonWithTitle: family.name, target: self, action: #selector(schemeChanged(_:)))
      choice.state = index == 0 ? .on : .off
      choice.font = .systemFont(ofSize: 14, weight: .medium)
      let detail = note(""), active = note("")
      active.textColor = .controlAccentColor
      schemeChoices.append(choice); schemeDetails.append(detail); schemeStates.append(active)
      let copy = vertical([choice, detail], spacing: 3)
      return settingRow(copy: copy, control: active, height: 72)
    }
    layoutRow = settingRow("双拼键位", control: layouts)
    let source = button("方案来源", #selector(openSchemeSource)); source.bezelStyle = .inline
    let input = page("输入方案", subtitle: "选择你习惯的拼音方案和输入方式。", views: [
      section("拼音方案", content: group(schemeRows)),
      actionRow(note("下载后保存在本机，可随时切换。"), [source]),
      section("输入方式", content: group([
        settingRow("拼音模式", control: inputMode), layoutRow,
        settingRow("使用英文标点", detail: "中文输入时使用半角标点", control: punctuation),
        settingRow("上屏后联想", detail: GlintTouchBar.isAvailable
          ? "仅供 Touch Bar 点选；键盘输入结束联想"
          : "未检测到 Touch Bar，此设备不启用联想", control: prediction)])),
      actionRow(schemeProgress, [cancelDownload, applyScheme]),
      section("中 / 英切换", content: note("使用 macOS 的中 / 英键切换 Glint 与 ABC；长按开启大写锁定。"))])
    applyScheme.bezelStyle = .rounded
    let previewGroup = group([settingRow("候选预览", control: previewMode, height: 42), preview])
    let fontSize = NSStackView(views: [size, sizeLabel]); fontSize.spacing = 12
    size.widthAnchor.constraint(equalToConstant: 180).isActive = true
    sizeLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
    sizeLabel.widthAnchor.constraint(equalToConstant: 40).isActive = true
    fonts.widthAnchor.constraint(equalToConstant: 230).isActive = true
    let appearance = page("候选外观", subtitle: "调整屏幕候选的样式，修改即时预览。", views: [previewGroup,
      group([settingRow("字体", control: fonts), settingRow("字号", control: fontSize), settingRow("外观", control: theme)]),
      actionRow(note("Touch Bar 跟随 macOS 的外观。"), [button("恢复默认", #selector(resetAppearance))])])
    let dictionaryChoice = NSStackView(views: [dictionaries, dictionaryName]); dictionaryChoice.spacing = 0
    dictionaryChoice.distribution = .fill
    dictionaries.setContentHuggingPriority(.required, for: .horizontal)
    dictionaryName.setContentHuggingPriority(.required, for: .horizontal)
    dictionaries.widthAnchor.constraint(lessThanOrEqualToConstant: 260).isActive = true
    dictionaryName.textColor = .secondaryLabelColor
    let dictionary = page("词库与学习", subtitle: "保留输入习惯，带上你常用的词。", views: [
      group([settingRow("学习词库", detail: "以下操作应用于所选词库", control: dictionaryChoice)]),
      section("学习数据", content: group([
        settingRow("备份学习数据", detail: "保存个人词条及使用频率", control: button("备份…", #selector(backup))),
        settingRow("恢复学习数据", detail: "将备份合并到现有词库", control: button("恢复…", #selector(restore)))])),
      section("词条交换", content: group([
        settingRow("导入词条", detail: "从 Rime 格式的文本文件导入", control: button("导入…", #selector(importText))),
        settingRow("导出词条", detail: "导出为可阅读、可编辑的文本", control: button("导出…", #selector(exportText)))])),
      section("更多词库", content: group([
        settingRow("专业词库", detail: "管理额外导入的领域词汇", control: button("管理…", #selector(manageProfessional))),
        settingRow("从鼠须管迁移", detail: "导入已有积累，保留原始文件", control: button("迁移…", #selector(migrate)))]))])
    let sync = page("iCloud 同步", subtitle: "让自己的词库在多台 Mac 之间延续。", views: [
      group([settingRow("通过 iCloud Drive 同步", detail: "使用当前 Mac 的 iCloud 账户", control: syncEnabled)]),
      section("同步内容", content: group([
        settingRow("个人学习数据", detail: "当前方案的个人词条与使用频率", control: note("始终包含")),
        settingRow("用户配置", detail: "同时同步自定义配置文件", control: syncConfig)])),
      section("同步频率", content: group([settingRow("自动同步", control: interval)])),
      note("成品方案、公共词库和模型保留在本机。每台 Mac 可独立选择方案与双拼键位。"),
      actionRow(syncStatus, [conflicts, synchronize])])
    syncStatus.font = .systemFont(ofSize: 12); syncStatus.maximumNumberOfLines = 3
    dataPath.font = .systemFont(ofSize: 11); dataPath.textColor = .secondaryLabelColor
    let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "开发版"
    let about = page("关于与诊断", subtitle: "版本信息、配置文件和排查工具。", views: [
      section("流光 Glint", content: group([
        settingRow("版本", control: note(version)), settingRow("输入引擎", control: note("librime \(RimeEngine.version)")),
        settingRow("平台", control: note("Apple Silicon"))])),
      section("文件与诊断", content: group([
        settingRow("数据目录", detail: "个人词库与已安装方案", control: button("打开…", #selector(openDataRoot))),
        settingRow("配置目录", detail: "当前方案的自定义配置", control: button("打开…", #selector(openData))),
        settingRow("诊断目录", detail: "查看运行、维护与同步日志", control: button("打开…", #selector(openLogs)))])),
      dataPath])
    pages = [input, appearance, dictionary, sync, about]
    status.font = .systemFont(ofSize: 11); status.textColor = .secondaryLabelColor
    status.maximumNumberOfLines = 2
    main.addSubview(status); status.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([status.leadingAnchor.constraint(equalTo: main.leadingAnchor, constant: 32),
      status.trailingAnchor.constraint(equalTo: main.trailingAnchor, constant: -32),
      status.bottomAnchor.constraint(equalTo: main.bottomAnchor, constant: -16), status.heightAnchor.constraint(equalToConstant: 32)])
    for page in pages {
      main.addSubview(page)
      NSLayoutConstraint.activate([page.topAnchor.constraint(equalTo: main.topAnchor, constant: 28),
        page.leadingAnchor.constraint(equalTo: main.leadingAnchor, constant: 32),
        page.trailingAnchor.constraint(equalTo: main.trailingAnchor, constant: -32),
        page.bottomAnchor.constraint(lessThanOrEqualTo: status.topAnchor, constant: -12)])
      page.isHidden = true
    }
    navigation.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
  }

  func numberOfRows(in tableView: NSTableView) -> Int { sections.count }
  func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
    let cell = NSTableCellView(), label = NSTextField(labelWithString: sections[row].0)
    let icon = NSImageView(image: NSImage(systemSymbolName: sections[row].1, accessibilityDescription: nil)!)
    label.font = .systemFont(ofSize: 13)
    cell.textField = label; cell.imageView = icon
    cell.addSubview(label); cell.addSubview(icon)
    label.translatesAutoresizingMaskIntoConstraints = false; icon.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([icon.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 8),
      icon.centerYAnchor.constraint(equalTo: cell.centerYAnchor), icon.widthAnchor.constraint(equalToConstant: 18),
      icon.heightAnchor.constraint(equalToConstant: 18), label.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 9),
      label.centerYAnchor.constraint(equalTo: cell.centerYAnchor), label.trailingAnchor.constraint(lessThanOrEqualTo: cell.trailingAnchor, constant: -6)])
    return cell
  }
  func tableViewSelectionDidChange(_ notification: Notification) {
    for (index, page) in pages.enumerated() { page.isHidden = index != navigation.selectedRow }
  }
  @objc private func openDataRoot() { NSWorkspace.shared.open(GlintInputController.dataRootURL) }

  private func note(_ text: String) -> NSTextField {
    let label = NSTextField(wrappingLabelWithString: text)
    label.font = .systemFont(ofSize: 12); label.textColor = .secondaryLabelColor
    return label
  }
  private func button(_ text: String, _ action: Selector) -> NSButton { NSButton(title: text, target: self, action: action) }
  private func vertical(_ views: [NSView], spacing: CGFloat) -> NSStackView {
    let stack = NSStackView(views: views)
    stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = spacing
    stack.translatesAutoresizingMaskIntoConstraints = false
    for view in views {
      view.translatesAutoresizingMaskIntoConstraints = false
      view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
      view.setContentHuggingPriority(.required, for: .vertical)
      view.setContentCompressionResistancePriority(.required, for: .vertical)
    }
    return stack
  }
  private func page(_ title: String, subtitle: String, views: [NSView]) -> NSView {
    let heading = NSTextField(labelWithString: title); heading.font = .systemFont(ofSize: 22, weight: .semibold)
    return vertical([vertical([heading, note(subtitle)], spacing: 6)] + views, spacing: 18)
  }
  private func section(_ title: String, content: NSView) -> NSView {
    let heading = note(title); heading.font = .systemFont(ofSize: 12, weight: .semibold)
    return vertical([heading, content], spacing: 8)
  }
  private func group(_ rows: [NSView]) -> NSView {
    let box = NSBox(); box.boxType = .custom; box.titlePosition = .noTitle
    box.isTransparent = false
    box.cornerRadius = 10
    box.fillColor = NSColor(name: nil) { appearance in
      appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        ? NSColor(srgbRed: 0.19, green: 0.19, blue: 0.20, alpha: 1) : .white
    }
    box.borderColor = .separatorColor; box.borderWidth = 0.5
    box.contentViewMargins = .zero
    let stack = vertical(rows, spacing: 0)
    box.contentView = stack
    for row in rows.dropFirst() {
      let separator = NSBox(); separator.boxType = .separator
      row.addSubview(separator); separator.translatesAutoresizingMaskIntoConstraints = false
      NSLayoutConstraint.activate([separator.leadingAnchor.constraint(equalTo: row.leadingAnchor),
        separator.trailingAnchor.constraint(equalTo: row.trailingAnchor), separator.topAnchor.constraint(equalTo: row.topAnchor)])
    }
    NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 1),
      stack.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -1),
      stack.topAnchor.constraint(equalTo: box.topAnchor, constant: 1),
      stack.bottomAnchor.constraint(equalTo: box.bottomAnchor, constant: -1)])
    return box
  }
  private func settingRow(_ title: String, detail: String? = nil, control: NSView, height: CGFloat? = nil) -> NSView {
    let label = NSTextField(labelWithString: title); label.font = .systemFont(ofSize: 13)
    control.setAccessibilityLabel(title)
    return settingRow(copy: detail.map { vertical([label, note($0)], spacing: 3) } ?? label,
      control: control, height: height ?? (detail == nil ? 48 : 56))
  }
  private func settingRow(copy: NSView, control: NSView, height: CGFloat) -> NSView {
    let row = NSView()
    row.addSubview(copy); row.addSubview(control)
    copy.translatesAutoresizingMaskIntoConstraints = false; control.translatesAutoresizingMaskIntoConstraints = false
    control.setContentHuggingPriority(.required, for: .horizontal)
    control.setContentCompressionResistancePriority(.required, for: .horizontal)
    NSLayoutConstraint.activate([row.heightAnchor.constraint(equalToConstant: height),
      copy.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 15), copy.centerYAnchor.constraint(equalTo: row.centerYAnchor),
      copy.trailingAnchor.constraint(equalTo: control.leadingAnchor, constant: -18),
      control.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -15), control.centerYAnchor.constraint(equalTo: row.centerYAnchor)])
    return row
  }
  private func actionRow(_ message: NSTextField, _ buttons: [NSButton]) -> NSView {
    let actions = NSStackView(views: buttons); actions.spacing = 8
    actions.distribution = .fill
    message.setContentHuggingPriority(.defaultLow, for: .horizontal)
    buttons.forEach {
      $0.setContentHuggingPriority(.required, for: .horizontal)
      $0.setContentCompressionResistancePriority(.required, for: .horizontal)
    }
    return settingRow(copy: message, control: actions, height: 42)
  }
}
