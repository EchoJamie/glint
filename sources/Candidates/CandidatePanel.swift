// Copyright (C) 2026 EchoJamie <echojamieee@outlook.com>
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit

/// 一份呈现中的候选身份。控制器闭包确定会话，代次作废旧组合的事件。
struct CandidateSelection: Equatable {
  let generation: UInt64
  let index: Int
}

/// 非激活窗口；布局、数字映射、命中测试共用同一份几何数据。
final class CandidatePanel: NSPanel {
  struct Item: Equatable {
    let index: Int
    let text: String
    let comment: String?
  }
  enum Layout: Equatable { case compact, expanded }

  var onPick: ((CandidateSelection) -> Void)?
  var onHighlight: ((CandidateSelection) -> Void)?
  var onNeedMore: (() -> Void)?
  var onLayoutChanged: (() -> Void)?
  private(set) var accessibleCandidates: [NSAccessibilityElement] = []
  private let scrollView = CandidateScrollView()
  private let listView = CandidateListView()
  private static let verticalInset: CGFloat = 4
  private var updating = false
  private var generation: UInt64 = 0
  private var presentedAt: TimeInterval = 0
  private var expandedOrigin: NSPoint = .zero
  private var widthLimit: CGFloat = 480
  private var heightLimit: CGFloat = 216
  private(set) var layout: Layout = .compact
  private(set) var items: [Item] = []

  var highlighted: Int? { listView.highlighted }
  var viewport: NSRect { scrollView.documentVisibleRect }
  var documentSize: NSSize { listView.frame.size }
  var numberedSelections: [Int: CandidateSelection] {
    listView.numbers.reduce(into: [:]) { result, entry in
      result[entry.value] = selection(at: entry.key)
    }
  }

  override var canBecomeKey: Bool { false }
  override var canBecomeMain: Bool { false }

  init() {
    super.init(contentRect: NSRect(x: 0, y: 0, width: 480, height: 36),
               styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    isFloatingPanel = true
    becomesKeyOnlyIfNeeded = true
    worksWhenModal = true
    level = .popUpMenu
    collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    hidesOnDeactivate = false
    isOpaque = false
    backgroundColor = .clear
    hasShadow = true
    isMovable = false
    isReleasedWhenClosed = false

    let container = CandidateBackgroundView()
    contentView = container
    container.addSubview(scrollView)
    scrollView.drawsBackground = false
    scrollView.hasHorizontalScroller = false
    scrollView.hasVerticalScroller = false
    scrollView.horizontalScrollElasticity = .none
    scrollView.verticalScrollElasticity = .none
    scrollView.documentView = listView
    scrollView.contentView.postsBoundsChangedNotifications = true
    NotificationCenter.default.addObserver(self, selector: #selector(didScroll),
      name: NSView.boundsDidChangeNotification, object: scrollView.contentView)
    scrollView.beforeScroll = { [weak self] in self?.setLayout(.expanded) }
    listView.setAccessibilityElement(true)
    listView.setAccessibilityRole(.list)
    listView.setAccessibilityLabel("流光候选")
    applyAppearance(GlintPreferences.shared.appearance)
    NotificationCenter.default.addObserver(self, selector: #selector(preferencesChanged),
      name: GlintPreferences.changed, object: nil)
    listView.onClick = { [weak self] position, count, timestamp in
      guard let self, timestamp >= self.presentedAt,
            let selection = self.selection(at: position) else { return }
      self.stopScrolling()
      if count == 1 { self.onHighlight?(selection) }
      if count == 2 { self.onPick?(selection) }
    }
  }

  deinit { NotificationCenter.default.removeObserver(self) }

  @objc private func preferencesChanged() { applyAppearance(GlintPreferences.shared.appearance) }

  func applyAppearance(_ value: CandidateAppearance) {
    appearance = value.theme == .system ? nil : NSAppearance(named: value.theme == .dark ? .darkAqua : .aqua)
    listView.applyAppearance(value)
    relayout(origin: viewport.origin)
    onLayoutChanged?()
  }

  /// 示例与实际窗口复用同一布局及绘制实现，不读取用户词典。
  static func preview(_ value: CandidateAppearance, expanded: Bool = false) -> NSView {
    let view = CandidateListView()
    view.items = ["你好", "拟好", "你", "尼", "泥", "逆", "倪", "腻"].enumerated().map {
      .init(index: $0.offset, text: $0.element, comment: nil)
    }
    view.highlighted = 0
    view.applyAppearance(value)
    view.rebuild(width: 510, grid: expanded)
    if !expanded {
      view.items = Array(view.items.prefix(view.rows.first?.count ?? 0))
      view.rebuild(width: 510)
    }
    view.numbers = Dictionary(uniqueKeysWithValues: view.items.indices.map { ($0, $0 + 1) })
    let background = CandidateBackgroundView()
    background.appearance = view.appearance
    background.frame = NSRect(x: 0, y: 0, width: view.frame.width, height: view.frame.height + verticalInset * 2)
    view.frame.origin.y = verticalInset
    background.addSubview(view)
    return background
  }

  func setItems(_ newItems: [Item], generation: UInt64) {
    let newRound = self.generation != generation
    self.generation = generation
    items = newItems
    listView.items = newItems
    if newRound {
      layout = .compact
      expandedOrigin = .zero
      listView.highlighted = newItems.isEmpty ? nil : 0
      presentedAt = ProcessInfo.processInfo.systemUptime
    }
    relayout(origin: newRound ? .zero : viewport.origin)
  }

  func setHighlighted(_ position: Int?, reveal: Bool = true) {
    guard let position, items.indices.contains(position) else {
      listView.highlighted = nil
      return
    }
    listView.highlighted = position
    if layout == .compact {
      relayout(origin: viewport.origin)
    } else if reveal {
      updating = true
      listView.scrollToVisible(listView.rects[position])
      updating = false
      updateNumbers()
    } else {
      updateNumbers()
    }
  }

  func constrain(to screenSize: NSSize) {
    let width = min(480, screenSize.width * 0.8)
    let height = min(216, screenSize.height * 0.35 - Self.verticalInset * 2)
    guard width != widthLimit || height != heightLimit else { return }
    widthLimit = width
    heightLimit = height
    relayout(origin: viewport.origin)
    if let highlighted { setHighlighted(highlighted) }
  }

  func setLayout(_ value: Layout) {
    guard layout != value else { return }
    if layout == .expanded { expandedOrigin = viewport.origin }
    layout = value
    relayout(origin: value == .expanded ? expandedOrigin : viewport.origin)
    if value == .expanded {
      if let highlighted { setHighlighted(highlighted) }
      requestMoreIfNeeded()
    }
    onLayoutChanged?()
  }

  func stopScrolling() { scrollView.ignoreMomentum = true }

  func selection(at position: Int) -> CandidateSelection? {
    guard items.indices.contains(position) else { return nil }
    return CandidateSelection(generation: generation, index: items[position].index)
  }

  /// 展开后的上下键按显示行与水平位置移动；左右键按候选顺序移动。
  func positionForMove(horizontal: Int = 0, vertical: Int = 0) -> Int? {
    guard let current = highlighted, listView.rects.indices.contains(current) else { return nil }
    if horizontal != 0 {
      return min(max(0, current + horizontal), items.count - 1)
    }
    guard let row = listView.rows.firstIndex(where: { $0.contains(current) }) else { return nil }
    let target = row + vertical
    guard listView.rows.indices.contains(target) else { return current }
    let x = listView.rects[current].midX
    return listView.rows[target].min { abs(listView.rects[$0].midX - x) < abs(listView.rects[$1].midX - x) }
  }

  var isHighlightInLastRow: Bool { listView.rows.last?.contains(highlighted ?? -1) == true }
  var isHighlightInFirstRow: Bool { listView.rows.first?.contains(highlighted ?? -1) == true }
  var isHighlightInFirstColumn: Bool {
    listView.rows.first { $0.contains(highlighted ?? -1) }?.first == highlighted
  }

  private func relayout(origin: NSPoint) {
    updating = true
    defer { updating = false }
    presentedAt = ProcessInfo.processInfo.systemUptime
    listView.rebuild(width: max(80, widthLimit), grid: layout == .expanded)
    let row = listView.row(containing: highlighted ?? 0)
    let height = layout == .expanded ? min(heightLimit, listView.frame.height) : row.height
    let positions = listView.rows.first { $0.contains(highlighted ?? 0) } ?? []
    let rowWidth = positions.last.map { listView.rects[$0].maxX + 8 } ?? 52
    let size = NSSize(width: layout == .expanded ? widthLimit : min(widthLimit, rowWidth),
                      height: max(36, height) + Self.verticalInset * 2)
    setContentSize(size)
    scrollView.frame = NSRect(x: 0, y: Self.verticalInset, width: size.width, height: size.height - Self.verticalInset * 2)
    let y = layout == .compact ? row.minY : min(origin.y, max(0, listView.frame.height - height))
    scrollView.contentView.scroll(to: NSPoint(x: 0, y: max(0, y)))
    scrollView.reflectScrolledClipView(scrollView.contentView)
    invalidateShadow()
    updateNumbers()
  }

  @objc private func didScroll() {
    guard !updating, layout == .expanded else { return }
    let visible = viewport
    if let highlighted, !listView.rects[highlighted].intersects(visible) {
      let row = listView.rows.first { positions in
        let rect = listView.row(containing: positions[0])
        return visible.contains(rect)
      }
      let next = row?.first ?? listView.rects.firstIndex { $0.intersects(visible) }
      if let next, let selection = selection(at: next) { onHighlight?(selection) }
    }
    updateNumbers()
    requestMoreIfNeeded()
    onLayoutChanged?()
  }

  private func requestMoreIfNeeded() {
    if layout == .expanded, viewport.maxY >= listView.frame.height - 72 { onNeedMore?() }
  }

  private func updateNumbers() {
    let row = listView.rows.first { $0.contains(highlighted ?? 0) } ?? []
    let visible = row.filter { viewport.contains(listView.rects[$0]) }
    listView.numbers = Dictionary(uniqueKeysWithValues: visible.prefix(9).enumerated().map { ($0.element, $0.offset + 1) })
    accessibleCandidates = listView.rects.indices.filter { listView.rects[$0].intersects(viewport) }.map { position in
      let element = CandidateAccessibilityElement()
      let candidate = items[position]
      let identity = selection(at: position)!
      element.setAccessibilityParent(listView)
      element.setAccessibilityRole(.button)
      element.setAccessibilityEnabled(true)
      element.setAccessibilityLabel([candidate.text, candidate.comment].compactMap { $0 }.joined(separator: "，"))
      element.setAccessibilitySelected(highlighted == position)
      element.setAccessibilityHelp("确认候选")
      element.setAccessibilityFrameInParentSpace(listView.rects[position])
      element.onPress = { [weak self] in
        guard let self, identity.generation == self.generation,
              self.items.contains(where: { $0.index == identity.index }) else { return false }
        self.stopScrolling()
        self.onPick?(identity)
        return true
      }
      return element
    }
    listView.setAccessibilityChildren(accessibleCandidates)
    listView.needsDisplay = true
    listView.displayIfNeeded()
  }

  // 诊断调用与真实事件共用几何和回调；不发布系统输入事件。
  func point(for position: Int) -> NSPoint? {
    guard listView.rects.indices.contains(position) else { return nil }
    let rect = listView.rects[position]
    return NSPoint(x: rect.midX, y: rect.midY)
  }
  func simulateClick(position: Int, count: Int, timestamp: TimeInterval? = nil) {
    guard let point = point(for: position), let event = NSEvent.mouseEvent(
      with: .leftMouseDown, location: listView.convert(point, to: nil), modifierFlags: [],
      timestamp: timestamp ?? ProcessInfo.processInfo.systemUptime, windowNumber: windowNumber,
      context: nil, eventNumber: 0, clickCount: count, pressure: 1) else { return }
    listView.mouseDown(with: event)
  }
  func scroll(to y: CGFloat) {
    scrollView.contentView.scroll(to: NSPoint(x: 0, y: max(0, min(y, documentSize.height - viewport.height))))
    scrollView.reflectScrolledClipView(scrollView.contentView)
    didScroll()
  }
}

/// 浮窗和设置预览共用系统材质；明暗及减少透明度由 AppKit 处理。
private final class CandidateBackgroundView: NSVisualEffectView {
  init() {
    super.init(frame: .zero)
    material = .popover
    blendingMode = .behindWindow
    state = .active // 候选窗口不获取键盘焦点，不能跟随非激活状态变灰。
    wantsLayer = true
    layer?.cornerRadius = 10
    layer?.masksToBounds = true
    layer?.borderWidth = 0.5
    updateBorder()
  }
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    updateBorder()
  }
  private func updateBorder() {
    effectiveAppearance.performAsCurrentDrawingAppearance {
      layer?.borderColor = NSColor.labelColor.withAlphaComponent(0.16).cgColor
    }
  }
}

private final class CandidateAccessibilityElement: NSAccessibilityElement {
  var onPress: (() -> Bool)?
  override func accessibilityPerformPress() -> Bool { onPress?() ?? false }
}

private final class CandidateScrollView: NSScrollView {
  var beforeScroll: (() -> Void)?
  var ignoreMomentum = false
  override func scrollWheel(with event: NSEvent) {
    if ignoreMomentum && !event.momentumPhase.isEmpty { return }
    ignoreMomentum = false
    beforeScroll?()
    super.scrollWheel(with: event)
  }
}

private final class CandidateListView: NSView {
  var items: [CandidatePanel.Item] = []
  var highlighted: Int?
  var numbers: [Int: Int] = [:]
  var onClick: ((Int, Int, TimeInterval) -> Void)?
  private(set) var rects: [NSRect] = []
  private(set) var rows: [[Int]] = []
  private var font = NSFont.systemFont(ofSize: 18)
  func applyAppearance(_ value: CandidateAppearance) {
    font = NSFontManager.shared.font(withFamily: value.fontName, traits: [], weight: 5, size: value.fontSize) ?? NSFont.systemFont(ofSize: value.fontSize)
    appearance = value.theme == .system ? nil : NSAppearance(named: value.theme == .dark ? .darkAqua : .aqua)
    needsDisplay = true
  }
  private let numberFont = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
  override var isFlipped: Bool { true }
  override var wantsDefaultClipping: Bool { true }

  private func text(_ item: CandidatePanel.Item, selected: Bool) -> NSAttributedString {
    let result = NSMutableAttributedString(string: item.text, attributes: [
      .font: font, .foregroundColor: selected ? NSColor.selectedMenuItemTextColor : NSColor.labelColor])
    if let comment = item.comment, !comment.isEmpty {
      result.append(NSAttributedString(string: "  " + comment, attributes: [
        .font: NSFont.systemFont(ofSize: 11),
        .foregroundColor: selected ? NSColor.selectedMenuItemTextColor : NSColor.labelColor.withAlphaComponent(0.8)]))
    }
    return result
  }

  func rebuild(width: CGFloat, grid: Bool = false) {
    rects = []; rows = []
    var row: [Int] = []
    var x: CGFloat = 8, y: CGFloat = 0, rowHeight: CGFloat = 36
    let available = width - 16
    // 紧凑按词宽排列；展开用稳定列宽，长词跨列。追加候选不会改变已有列。
    let minimumCell = ceil(("候选" as NSString).size(withAttributes: [.font: font]).width) + 24
    let columns = max(1, min(9, Int((available + 8) / (minimumCell + 8))))
    let cell = (available + 8) / CGFloat(columns)
    for (position, item) in items.enumerated() {
      let string = text(item, selected: false)
      let naturalWidth = ceil(string.size().width) + 24
      let itemWidth = min(available, grid ? ceil((naturalWidth + 8) / cell) * cell - 8 : naturalWidth)
      if !row.isEmpty && (row.count == 9 || x + itemWidth > width - 8 + 0.01) {
        rows.append(row); row = []; x = 8; y += rowHeight; rowHeight = 36
      }
      let textHeight = ceil(string.boundingRect(with: NSSize(width: itemWidth - 24, height: .greatestFiniteMagnitude),
        options: [.usesLineFragmentOrigin, .usesFontLeading]).height)
      let height = max(36, textHeight + 12)
      rects.append(NSRect(x: x, y: y, width: itemWidth, height: height))
      row.append(position); x += itemWidth + 8; rowHeight = max(rowHeight, height)
    }
    if !row.isEmpty { rows.append(row); y += rowHeight }
    frame = NSRect(x: 0, y: 0, width: width, height: max(36, y))
  }

  func row(containing position: Int) -> NSRect {
    guard let row = rows.first(where: { $0.contains(position) }) else {
      return NSRect(x: 0, y: 0, width: frame.width, height: 36)
    }
    return NSRect(x: 0, y: rects[row[0]].minY, width: frame.width,
                  height: row.map { rects[$0].height }.max() ?? 36)
  }

  override func draw(_ dirtyRect: NSRect) {
    for position in items.indices where rects[position].intersects(dirtyRect) {
      let rect = rects[position].insetBy(dx: 0, dy: 2)
      let selected = highlighted == position
      if selected {
        NSColor.controlAccentColor.setFill()
        NSBezierPath(roundedRect: rect, xRadius: 5, yRadius: 5).fill()
      }
      if let number = numbers[position] {
        (String(number) as NSString).draw(at: NSPoint(x: rect.minX + 4, y: rect.minY + 9),
          withAttributes: [.font: numberFont, .foregroundColor: selected ? NSColor.selectedMenuItemTextColor : NSColor.labelColor.withAlphaComponent(0.8)])
      }
      text(items[position], selected: selected).draw(with: NSRect(x: rect.minX + 20, y: rect.minY + 4,
        width: rect.width - 24, height: rect.height - 8), options: [.usesLineFragmentOrigin, .usesFontLeading])
    }
  }

  override func mouseDown(with event: NSEvent) {
    let point = convert(event.locationInWindow, from: nil)
    guard let position = rects.firstIndex(where: { $0.contains(point) }) else { return }
    onClick?(position, event.clickCount, event.timestamp)
  }
}
